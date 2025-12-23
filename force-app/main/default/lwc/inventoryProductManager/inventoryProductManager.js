import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getProducts from '@salesforce/apex/InventoryApiService.getProducts';
import generateQuoteAndSave from '@salesforce/apex/OpportunityQuotePDFController.generateQuoteAndSave';
import getQualityOptions from '@salesforce/apex/QualityConfigController.getQualityOptions';

export default class InventoryProductManager extends LightningElement {
    @api recordId;

    @track products = [];
    @track cartItems = [];
    @track selectedRoomType = null;
    @track selectedCategory = null;

    qualityConfig = [];

    @track isLoading = false;
    @track isCartOpen = false;

    @track showPopup = false;
    popupTitle = '';
    popupMessage = '';
    
    showCustomPopup(title, message) {
    this.popupTitle = title;
    this.popupMessage = message;
    this.showPopup = true;
}

closePopup() {
    this.showPopup = false;
}


    /* ---------------- STATIC DATA ---------------- */
    roomTypesBase = [
        'Bedroom','Living Room','Kitchen','Bathroom',
        'Dining Hall','Work Space','Cabin Room','Conference Hall'
    ];

    categoriesBase = [
        'Flooring','Ceiling','Electrical and Lighting',
        'Woodwork and Furniture','Walls and Paintings','Plumbing'
    ];

    /* ---------------- COMMUNITY PARAM ---------------- */
    @wire(CurrentPageReference)
getPageRef(pageRef) {
    if (pageRef && pageRef.state && pageRef.state.id) {
        this.recordId = pageRef.state.id;
    }
}

    connectedCallback() {
        this.loadQualityOptions();
    }

    /* ---------------- QUALITY CONFIG ---------------- */
    loadQualityOptions() {
        getQualityOptions()
            .then(res => this.qualityConfig = res || [])
            .catch(() => this.showToast('Error', 'Failed to load quality options', 'error'));
    }

    /* ---------------- GETTERS ---------------- */
    get cartTotal() {
        return this.cartItems.reduce((s, i) => s + (i.Total_Amount__c || 0), 0);
    }

    get cartLabel() {
        return `Cart (${this.cartItems.length})`;
    }

    get roomTypes() {
        return this.roomTypesBase.map(v => ({
            value: v,
            className: 'chip ' + (this.selectedRoomType === v ? 'chip-selected' : '')
        }));
    }

    get categories() {
        return this.categoriesBase.map(v => ({
            value: v,
            className: 'chip ' + (this.selectedCategory === v ? 'chip-selected' : '')
        }));
    }

    get selectedProductsList() {
        return this.cartItems.map(i => ({
            name: i.Name,
            qty: i.Quantity__c,
            quality: i.Quality__c || 'Standard'
        }));
    }

    /* ---------------- FILTER HANDLERS ---------------- */
    handleRoomSelect(event) {
        this.selectedRoomType = event.currentTarget.dataset.value;
        this.selectedCategory = null;
        this.products = [];
    }

    handleCategorySelect(event) {
        this.selectedCategory = event.currentTarget.dataset.value;
        this.loadProducts();
    }

    /* ---------------- LOAD PRODUCTS ---------------- */
    loadProducts() {
        if (!this.selectedRoomType || !this.selectedCategory) return;

        this.isLoading = true;

        getProducts({
            roomType: this.selectedRoomType,
            category: this.selectedCategory
        })
        .then(result => {
            this.products = (result || []).map(p => {
                const cartItem = this.cartItems.find(c => c.Interior_Product__c === p.Id);

                const quality = cartItem?.Quality__c || 'Standard';
                const price = cartItem?.Unit_Price__c || p.Unit_Price__c;

                return {
                    ...p,
                    qualityGroupName: `quality-${p.Id}`,
                    standardId: `standard-${p.Id}`,
                    premiumId: `premium-${p.Id}`,
                    luxuryId: `luxury-${p.Id}`,

                    qty: cartItem ? cartItem.Quantity__c : 0,
                    inCart: !!cartItem,

                    selectedQuality: quality,
                    displayPrice: price,

                    isStandard: quality === 'Standard',
                    isPremium: quality === 'Premium',
                    isLuxury: quality === 'Luxury',

                    imageUrl: this.buildImageUrl(p)
                };
            });
        })
        .catch(() => this.showToast('Error', 'Failed to load products', 'error'))
        .finally(() => this.isLoading = false);
    }

    /* ---------------- QUALITY RADIO ---------------- */
    handleQualityRadio(event) {
        const productId = event.currentTarget.dataset.id;
        const selectedQuality = event.target.value;

        const prod = this.products.find(p => p.Id === productId);
        if (!prod) return;

        const cfg = this.qualityConfig.find(q => q.Quality__c === selectedQuality);
        const multiplier = cfg ? cfg.Multiplier__c : 1;
        const newPrice = Math.round(prod.Unit_Price__c * multiplier);

        this.products = this.products.map(p =>
            p.Id === productId
                ? {
                    ...p,
                    selectedQuality,
                    displayPrice: newPrice,
                    isStandard: selectedQuality === 'Standard',
                    isPremium: selectedQuality === 'Premium',
                    isLuxury: selectedQuality === 'Luxury'
                }
                : p
        );
    }

    /* ---------------- CART ---------------- */
    handleAddToCart(event) {
        const productId = event.currentTarget.dataset.id;
        const prod = this.products.find(p => p.Id === productId);
        if (!prod) return;

        this.updateQty(productId, 1, prod.displayPrice, prod.selectedQuality);
    }

    handleQtyPlus(event) {
        const productId = event.currentTarget.dataset.id;
        const prod = this.products.find(p => p.Id === productId);
        this.updateQty(productId, prod.qty + 1, prod.displayPrice, prod.selectedQuality);
    }

    handleQtyMinus(event) {
        const productId = event.currentTarget.dataset.id;
        const prod = this.products.find(p => p.Id === productId);
        this.updateQty(productId, Math.max(prod.qty - 1, 0), prod.displayPrice, prod.selectedQuality);
    }

    updateQty(productId, qty, price, quality) {
        let cart = [...this.cartItems];
        const idx = cart.findIndex(c => c.Interior_Product__c === productId);

        if (qty > 0) {
            if (idx >= 0) {
                cart[idx] = {
                    ...cart[idx],
                    Quantity__c: qty,
                    Unit_Price__c: price,
                    Quality__c: quality,
                    Total_Amount__c: qty * price
                };
            } else {
                cart.push({
                    sobjectType: 'Project_Specification__c',
                    Opportunity__c: this.recordId,
                    Interior_Product__c: productId,
                    Name: this.products.find(p => p.Id === productId)?.Name,
                    Quantity__c: qty,
                    Unit_Price__c: price,
                    Quality__c: quality,
                    Total_Amount__c: qty * price
                });
            }
        } else {
            cart = cart.filter(c => c.Interior_Product__c !== productId);
        }

        this.cartItems = cart;

        // rehydrate UI from cart
        this.products = this.products.map(p => {
            const item = cart.find(c => c.Interior_Product__c === p.Id);
            if (!item) return { ...p, qty: 0, inCart: false };

            return {
                ...p,
                qty: item.Quantity__c,
                inCart: true,
                selectedQuality: item.Quality__c,
                displayPrice: item.Unit_Price__c,
                isStandard: item.Quality__c === 'Standard',
                isPremium: item.Quality__c === 'Premium',
                isLuxury: item.Quality__c === 'Luxury'
            };
        });
    }

    /* ---------------- CART MODAL ---------------- */
    openCart() {
        this.isCartOpen = true;
    }

    closeCart() {
        this.isCartOpen = false;
    }
    handleClearCart() {
        this.cartItems = [];
        this.products = this.products.map(p => ({
            ...p,
            qty: 0,
            inCart: false,
            selectedQuality: 'Standard',
            displayPrice: p.Unit_Price__c,
            isStandard: true,
            isPremium: false,
            isLuxury: false
        }));
        this.closeCart();
        this.showToast('Cleared', 'Cart cleared successfully', 'success');
    }


    /* ---------------- GENERATE QUOTE ---------------- */
    handleGenerateQuote() {
    if (!this.cartItems.length) {
    this.showCustomPopup(
        '⚠️ Cart Empty',
        'Add items before generating quotation.'
    );
    return;
}


        generateQuoteAndSave({
        opportunityId: this.recordId,
        cartItems: this.cartItems
    })
        .then(() => {
    this.showCustomPopup(
        '🎉 Quotation Generated',
        'PDF created successfully & project items saved.'
    );
})
        .catch(e => {
            this.showToast('Error', e.body?.message || 'Unknown error', 'error');
        });
}


    /* ---------------- IMAGE (STATIC RESOURCE) ---------------- */
    buildImageUrl(product) {
        return product?.Image_File_Name__c
            ? `/resource/${product.Image_File_Name__c}`
            : '/resource/Default_Product_Image';
    }

    /* ---------------- UI HELPERS ---------------- */
    showPopup(title, message) {
        this.popupTitle = title;
        this.popupMessage = message;
        this.showPopup = true;
    }

    closePopup() {
        this.showPopup = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant,
            mode: 'sticky'
        }));
    }
    
}