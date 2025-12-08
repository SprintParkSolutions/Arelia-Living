import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import getMasterData from '@salesforce/apex/InteriorMasterService.getMasterData';
import saveRequest from '@salesforce/apex/InteriorAutoProjectRequestService.saveRequest';
import fetchLeadForAutoRequest
    from '@salesforce/apex/InteriorAutoProjectRequestService.fetchLeadForAutoRequest';
import fetchExistingRequest
    from '@salesforce/apex/InteriorAutoProjectRequestService.fetchExistingRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import SITE_URL from '@salesforce/label/c.Arelia_Site_Label';

export default class AreliaAutomaticProjectRequestComp extends LightningElement {
    @api leadId;
    @api quotationType;

    @track currentStep = 1;

    // master data
    allProjectTypes = [];
    allCategories = [];
    allRooms = [];
    allDesigns = [];
    allPlanLevels = [];

    // step1 fields
    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    address = '';
    siteSpace = '';
    description = '';

    // selections
    selectedProjectTypeId;
    selectedCategoryId;
    @track roomQuantities = {}; // {roomId: qty}
    selectedPlanLevel;
    currentRoomIdForDesign;
    @track roomDesignMap = {}; // {roomId: {designId,...}}

    // totals (stored in USD from Base_Price__c)
    totalBudget = 0;

    // flags
    @track isImageModalOpen = false;
    modalImageUrl;
    modalTitle;

    isSaving = false;

    // initial loading
    @track isInitLoading = true;
    hasInitLoaded = false;

    // has existing automatic request already saved?
    hasExistingRequest = false;

    labels = {
        siteUrl: SITE_URL
    };

    /* -----------------------------
       HOW WE GET LEAD ID
       ----------------------------- */

    connectedCallback() {
        this.ensureInitialLoad();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (!pageRef) {
            return;
        }

        const idFromUrl =
            (pageRef.state && pageRef.state.id) ||
            (pageRef.state && pageRef.state.c__id);

        if (idFromUrl && idFromUrl !== this.leadId) {
            this.leadId = idFromUrl;
        }

        this.ensureInitialLoad();
    }

    renderedCallback() {
        this.ensureInitialLoad();
    }

    ensureInitialLoad() {
        if (this.hasInitLoaded) {
            return;
        }
        if (!this.leadId) {
            return;
        }
        this.loadInitialData();
    }

    /* -----------------------------
       Initial data load
       ----------------------------- */

    loadInitialData() {
        if (this.hasInitLoaded || !this.leadId) {
            return;
        }

        this.isInitLoading = true;
        this.hasInitLoaded = true;

        const masterPromise = getMasterData();
        const leadPromise = fetchLeadForAutoRequest({ leadId: this.leadId });
        const existingPromise = fetchExistingRequest({ leadId: this.leadId });

        Promise.all([masterPromise, leadPromise, existingPromise])
            .then(([res, leadRec, existing]) => {
                // master data
                this.allProjectTypes = res.projectTypes || [];
                this.allCategories = res.categories || [];
                this.allRooms = res.rooms || [];
                this.allDesigns = res.designs || [];
                this.allPlanLevels = res.designLevels || [];

                // lead pre-fill
                if (leadRec) {
                    this.applyLeadDefaults(leadRec);
                }

                // previous automatic request (rooms + designs)
                if (existing) {
                    this.applyExistingRequest(existing);
                }
            })
            .catch((err) => {
                this.showToast(
                    'Error',
                    err && err.body && err.body.message
                        ? err.body.message
                        : 'Unable to load project data.',
                    'error'
                );
            })
            .finally(() => {
                this.isInitLoading = false;
            });
    }

    applyLeadDefaults(leadRec) {
        this.firstName = leadRec.FirstName || '';
        this.lastName = leadRec.LastName || '';
        this.email = leadRec.Email || '';
        this.phone = leadRec.Phone || '';
        this.address = leadRec.Site_Location__c || '';
        this.siteSpace = leadRec.Site_Space__c || '';
        this.description = leadRec.Project_Description__c || '';

        // total budget stored as USD
        this.totalBudget = leadRec.Estimated_Budget__c || 0;

        this.selectedProjectTypeId = leadRec.Interior_Project_Type__c || null;
        this.selectedCategoryId = leadRec.Interior_Category__c || null;
        this.selectedPlanLevel = leadRec.Plan_Level__c || null;

        if (!this.quotationType && leadRec.Project_Request_Quotation_Type__c) {
            // eslint-disable-next-line @lwc/lwc/no-api-reassignments
            this.quotationType = leadRec.Project_Request_Quotation_Type__c;
        }
    }

    /**
     * @description Apply previously saved rooms and room designs for this Lead.
     *              This is called on 2nd / 3rd time when the customer
     *              opens the automatic quotation page again.
     */
    applyExistingRequest(existing) {
        // 1) Rooms (quantities)
        const qtyMap = {};
        (existing.rooms || []).forEach((r) => {
            if (r.roomId && r.quantity && r.quantity > 0) {
                qtyMap[r.roomId] = r.quantity;
            }
        });
        this.roomQuantities = qtyMap;

        // 2) Designs per room
        const designMap = {};
        let total = 0;

        (existing.roomDesigns || []).forEach((line) => {
            if (!line.roomId || !line.designId) {
                return;
            }

            const design = (this.allDesigns || []).find((d) => d.id === line.designId);

            const qty = line.quantity || 1;
            const price = design && design.basePrice
                ? design.basePrice
                : (line.lineAmount && qty ? line.lineAmount / qty : 0);

            const lineAmount = line.lineAmount != null ? line.lineAmount : price * qty;

            designMap[line.roomId] = {
                designId: line.designId,
                designName: design ? design.name : 'Design',
                price,
                quantity: qty,
                lineAmount,
                imageUrl: design ? design.imageUrl : null
            };

            total += lineAmount;
        });

        this.roomDesignMap = designMap;
        this.totalBudget = total;

        // mark that this Lead already has an automatic request saved
        const hasRooms = Object.keys(qtyMap).length > 0;
        const hasDesigns = Object.keys(designMap).length > 0;
        this.hasExistingRequest = hasRooms || hasDesigns;

        // Ensure a current room is selected for Step 6 UI
        const roomIds = Object.keys(designMap);
        if (!this.currentRoomIdForDesign && roomIds.length) {
            this.currentRoomIdForDesign = roomIds[0];
        }
    }

    // navigation back to parent
    handlePreviousClick() {
        this.dispatchEvent(new CustomEvent('previous'));
    }

    /* -----------------------------
       Step helpers / computed
       ----------------------------- */

    get steps() {
        const labels = [
            'Customer',
            'Project Type',
            'Category',
            'Rooms',
            'Plan',
            'Room Designs',
            'Preview Designs',
            'Review'
        ];
        return labels.map((label, index) => {
            const stepNumber = index + 1;
            let cls = 'step-item';
            if (stepNumber === this.currentStep) {
                cls = 'step-item active';
            } else if (stepNumber < this.currentStep) {
                cls = 'step-item done';
            }
            return {
                number: stepNumber,
                label,
                cls
            };
        });
    }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isStep6() { return this.currentStep === 6; }
    get isStep7() { return this.currentStep === 7; }
    get isStep8() { return this.currentStep === 8; }
    get isFirst() { return this.currentStep === 1; }
    get nextLabel() {
        return this.currentStep === 8 ? (this.isSaving ? 'Saving…' : 'Save') : 'Next';
    }

    get projectTypeOptions() {
        return (this.allProjectTypes || []).map((pt) => ({
            label: pt.name,
            value: pt.id,
            cardClass:
                pt.id === this.selectedProjectTypeId
                    ? 'choice-card selected'
                    : 'choice-card'
        }));
    }

    get categoryCards() {
        return (this.allCategories || [])
            .filter((c) => c.projectTypeId === this.selectedProjectTypeId)
            .map((c) => ({
                label: c.name,
                value: c.id,
                cardClass:
                    c.id === this.selectedCategoryId
                        ? 'choice-card selected'
                        : 'choice-card'
            }));
    }

    get roomsWithQty() {
        return (this.allRooms || [])
            .filter((r) => r.categoryId === this.selectedCategoryId)
            .map((r) => ({
                ...r,
                quantity: this.roomQuantities[r.id] || 0
            }));
    }

    get planOptions() {
        return (this.allPlanLevels || []).map((lvl) => ({
            label: lvl,
            value: lvl,
            cardClass:
                lvl === this.selectedPlanLevel
                    ? 'choice-card selected'
                    : 'choice-card'
        }));
    }

    get selectedRoomList() {
        const list = [];
        for (const roomId in this.roomQuantities) {
            if (!Object.prototype.hasOwnProperty.call(this.roomQuantities, roomId)) {
                continue;
            }
            const qty = this.roomQuantities[roomId];
            if (qty <= 0) {
                continue;
            }
            const room = this.allRooms.find((x) => x.id === roomId);
            const rd = this.roomDesignMap[roomId];
            list.push({
                id: roomId,
                name: room ? room.name : roomId,
                quantity: qty,
                selectedDesignName: rd ? rd.designName : 'No design selected',
                cardClass:
                    roomId === this.currentRoomIdForDesign
                        ? 'room-sel-card active'
                        : 'room-sel-card'
            });
        }

        if (!this.currentRoomIdForDesign && list.length) {
            this.currentRoomIdForDesign = list[0].id;
        }
        return list;
    }

    get currentRoomDesigns() {
        if (!this.currentRoomIdForDesign) {
            return [];
        }
        return (this.allDesigns || [])
            .filter(
                (d) =>
                    d.roomId === this.currentRoomIdForDesign &&
                    (!this.selectedPlanLevel || d.designLevel === this.selectedPlanLevel)
            )
            .map((d) => {
                const selectedForRoom = this.roomDesignMap[this.currentRoomIdForDesign];
                const isSelected = selectedForRoom && selectedForRoom.designId === d.id;
                return {
                    ...d,
                    itemClass: isSelected
                        ? 'design-item-tile selected'
                        : 'design-item-tile',
                    thumbUrl:
                        d.imageUrl || 'https://via.placeholder.com/220x140?text=Design',
                    fullImageUrl:
                        d.imageUrl || 'https://via.placeholder.com/1200x700?text=Design'
                };
            });
    }

    get selectedDesignTiles() {
        const tiles = [];
        for (const roomId in this.roomDesignMap) {
            if (!Object.prototype.hasOwnProperty.call(this.roomDesignMap, roomId)) {
                continue;
            }
            const rd = this.roomDesignMap[roomId];
            const room = this.allRooms.find((r) => r.id === roomId);
            const lineUsd = rd.lineAmount || 0;

            tiles.push({
                roomId,
                roomName: room ? room.name : roomId,
                designName: rd.designName,
                imageUrl:
                    rd.imageUrl || 'https://via.placeholder.com/220x140?text=Design',
                quantity: rd.quantity,
                lineAmountUsd: lineUsd
            });
        }
        return tiles;
    }

    get selectedProjectTypeName() {
        const f = this.allProjectTypes.find((p) => p.id === this.selectedProjectTypeId);
        return f ? f.name : '';
    }

    get selectedCategoryName() {
        const f = this.allCategories.find((c) => c.id === this.selectedCategoryId);
        return f ? f.name : '';
    }

    get selectedPlan() {
        return this.selectedPlanLevel || '';
    }

    get finalRoomDesignLines() {
        const out = [];
        for (const roomId in this.roomQuantities) {
            if (!Object.prototype.hasOwnProperty.call(this.roomQuantities, roomId)) {
                continue;
            }
            const qty = this.roomQuantities[roomId];
            if (!qty) {
                continue;
            }
            const room = this.allRooms.find((x) => x.id === roomId);
            const rd = this.roomDesignMap[roomId];
            if (rd) {
                const priceUsd = rd.price || 0;
                out.push(
                    `${room ? room.name : roomId} (x${qty}) – ${rd.designName} [ $ ${priceUsd} ]`
                );
            } else {
                out.push(`${room ? room.name : roomId} (x${qty}) – No design chosen`);
            }
        }
        return out;
    }

    // --- NEW: summary numbers for preview (Step 7) ---

    get roomsWithDesignCount() {
        return Object.keys(this.roomDesignMap || {}).length;
    }

    get totalRoomQuantity() {
        let total = 0;
        for (const roomId in this.roomQuantities) {
            if (!Object.prototype.hasOwnProperty.call(this.roomQuantities, roomId)) {
                continue;
            }
            const qty = this.roomQuantities[roomId];
            if (qty && qty > 0) {
                total += qty;
            }
        }
        return total;
    }

    /* -----------------------------
       Handlers
       ----------------------------- */

    handleInput(event) {
        const fld = event.target.dataset.field;
        this[fld] = event.target.value;
    }

    handleProjectTypeCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedProjectTypeId = id;
        this.selectedCategoryId = null;
        this.roomQuantities = {};
        this.selectedPlanLevel = null;
        this.roomDesignMap = {};
        this.currentRoomIdForDesign = null;
    }

    handleCategoryCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCategoryId = id;
        this.roomQuantities = {};
        this.selectedPlanLevel = null;
        this.roomDesignMap = {};
        this.currentRoomIdForDesign = null;
    }

    handleRoomIncrement(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.roomQuantities[id] || 0;
        this.roomQuantities = { ...this.roomQuantities, [id]: cur + 1 };
    }

    handleRoomDecrement(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.roomQuantities[id] || 0;
        const next = cur - 1;
        this.roomQuantities = { ...this.roomQuantities, [id]: next > 0 ? next : 0 };
    }

    handlePlanSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedPlanLevel = id;
        this.roomDesignMap = {};
        this.currentRoomIdForDesign = null;
    }

    handleRoomSelectForDesign(event) {
        this.currentRoomIdForDesign = event.currentTarget.dataset.id;
    }

    handleRoomDesignPick(event) {
        const designId = event.currentTarget.dataset.id;
        const design = this.allDesigns.find((x) => x.id === designId);
        if (!design || !this.currentRoomIdForDesign) {
            return;
        }

        const current = this.roomDesignMap[this.currentRoomIdForDesign];

        if (current && current.designId === designId) {
            const cloned = { ...this.roomDesignMap };
            delete cloned[this.currentRoomIdForDesign];
            this.roomDesignMap = cloned;
            this.recalcTotal();
            return;
        }

        const qty = this.roomQuantities[this.currentRoomIdForDesign] || 1;
        const priceUsd = design.basePrice || 0;
        const lineAmount = priceUsd * qty;

        this.roomDesignMap = {
            ...this.roomDesignMap,
            [this.currentRoomIdForDesign]: {
                designId: design.id,
                designName: design.name,
                price: priceUsd,
                quantity: qty,
                lineAmount,
                imageUrl: design.imageUrl
            }
        };
        this.recalcTotal();
    }

    handleRemoveSelected(event) {
        const roomId = event.currentTarget.dataset.roomid;
        const cloned = { ...this.roomDesignMap };
        delete cloned[roomId];
        this.roomDesignMap = cloned;
        this.recalcTotal();
    }

    openImageModal(event) {
        event.stopPropagation();
        this.modalImageUrl = event.currentTarget.dataset.img;
        this.modalTitle = event.currentTarget.dataset.title;
        this.isImageModalOpen = true;
    }

    closeImageModal() {
        this.isImageModalOpen = false;
        this.modalImageUrl = null;
        this.modalTitle = null;
    }

    handleImgError(event) {
        // eslint-disable-next-line no-param-reassign
        event.target.src = 'https://via.placeholder.com/220x140?text=No+Img';
    }

    handleNext() {
        if (this.isSaving) {
            return;
        }

        if (this.currentStep === 1) {
            if (
                !this.firstName ||
                !this.lastName ||
                !this.email ||
                !this.phone ||
                !this.siteSpace
            ) {
                this.showToast(
                    'Missing info',
                    'First Name, Last Name, Email, Phone and Site Space are required.',
                    'error'
                );
                return;
            }
        }

        if (this.currentStep === 2 && !this.selectedProjectTypeId) {
            this.showToast('Select project type', 'Please select a project type.', 'error');
            return;
        }

        if (this.currentStep === 3 && !this.selectedCategoryId) {
            this.showToast('Select category', 'Please select a category.', 'error');
            return;
        }

        if (this.currentStep === 4) {
            const quantities = Object.values(this.roomQuantities);
            const hasRoom = quantities.some((q) => q > 0);
            if (!hasRoom) {
                this.showToast('Select rooms', 'Please add at least one room.', 'error');
                return;
            }
        }

        if (this.currentStep === 5 && !this.selectedPlanLevel) {
            this.showToast('Select plan', 'Please select a plan/level.', 'error');
            return;
        }

        if (this.currentStep === 6) {
            const missingDesign = this.selectedRoomList.some(
                (r) => !this.roomDesignMap[r.id]
            );
            if (missingDesign) {
                this.showToast(
                    'Designs missing',
                    'Please choose a design for every room.',
                    'error'
                );
                return;
            }
            this.recalcTotal();
        }

        if (this.currentStep < 8) {
            this.currentStep += 1;
        } else {
            this.saveData();
        }
    }

    handlePrev() {
        if (this.currentStep > 1) {
            this.currentStep -= 1;
        }
    }

    recalcTotal() {
        let total = 0;
        for (const roomId in this.roomDesignMap) {
            if (!Object.prototype.hasOwnProperty.call(this.roomDesignMap, roomId)) {
                continue;
            }
            const info = this.roomDesignMap[roomId];
            total += info.lineAmount || 0;
        }
        this.totalBudget = total;
    }

    saveData() {
        // if already submitted once, do NOT call Apex again
        if (this.hasExistingRequest) {
            this.showToast(
                'Lead already submitted',
                'Lead details already submitted. If you have any queries contact Arelia Team.',
                'warning'
            );
            return;
        }

        this.isSaving = true;

        const rooms = [];
        for (const roomId in this.roomQuantities) {
            if (!Object.prototype.hasOwnProperty.call(this.roomQuantities, roomId)) {
                continue;
            }
            const qty = this.roomQuantities[roomId];
            if (qty && qty > 0) {
                rooms.push({ roomId, quantity: qty });
            }
        }

        const selectedRoomDesigns = [];
        for (const roomId in this.roomDesignMap) {
            if (!Object.prototype.hasOwnProperty.call(this.roomDesignMap, roomId)) {
                continue;
            }
            const rd = this.roomDesignMap[roomId];
            selectedRoomDesigns.push({
                roomId,
                designId: rd.designId,
                quantity: rd.quantity,
                lineAmount: rd.lineAmount
            });
        }

        const payload = {
            leadId: this.leadId,
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            address: this.address,
            siteSpace: this.siteSpace,
            description: this.description,
            projectTypeId: this.selectedProjectTypeId,
            categoryId: this.selectedCategoryId,
            planLevel: this.selectedPlanLevel,
            rooms,
            selectedRoomDesigns,
            totalBudget: this.totalBudget, // USD stored on Lead
            quotationType: this.quotationType
        };

        saveRequest({ req: payload })
            .then(() => {
                this.isSaving = false;
                // ✅ Show toast on success instead of overlay
                this.showToast(
                    'Project Request Submitted',
                    'Your automatic project details have been captured on the Lead. Our team will review and contact you shortly.',
                    'success'
                );

                // Optional: redirect back to site home / quotation page
                if (this.labels.siteUrl) {
                    window.setTimeout(() => {
                        window.location.href = this.labels.siteUrl;
                    }, 1500);
                }
            })
            .catch((err) => {
                this.isSaving = false;
                this.showToast(
                    'Error',
                    err && err.body && err.body.message
                        ? err.body.message
                        : 'Unable to submit project request.',
                    'error'
                );
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
