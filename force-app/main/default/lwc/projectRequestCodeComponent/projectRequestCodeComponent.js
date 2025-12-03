import { LightningElement, track, wire } from 'lwc';
import getProjectQuotationTypeValues from '@salesforce/apex/ProjectRequestController.getProjectQuotationTypeValues';
import updateQuotationType from '@salesforce/apex/ProjectRequestController.updateQuotationType';

export default class ProjectRequestCodeComponent extends LightningElement {
        // Screen control
    // @track showScreen1 = true;
    // @track showScreen2 = false;
    // @track leadId;

    // @track value = null;
    // @track options = [];

    // get disableNext() {
    //     return !this.value;
    // }

    // @wire(getProjectQuotationTypeValues)
    // wiredValues({ data, error }) {
    //     if (data) {
    //         this.options = data.map((label, index) => ({
    //             label,
    //             value: label,
    //             cssClass: `radio-row animate-stagger stagger-${index}`,
    //             selected: false
    //         }));
    //     } else if (error) {
    //         console.error('Error loading picklist values', error);
    //     }
    // }

    // handleChange(event) {
    //     this.value = event.target.value;

    //     this.options = this.options.map(opt => ({
    //         ...opt,
    //         selected: opt.value === this.value
    //     }));
    // }

    // handleRipple(event) {
    //     const ripple = event.currentTarget.querySelector('.ripple');
    //     if (ripple) {
    //         ripple.classList.remove('run');
    //         void ripple.offsetWidth;
    //         ripple.classList.add('run');
    //     }
    // }

    // goNext() {
    //     if (this.value === 'Manual Quotation') {
    //         // ✅ Extract Lead Id from URL
    //         const urlParams = new URLSearchParams(window.location.search);
    //         this.leadId = urlParams.get('id');

    //         this.showScreen1 = false;
    //         this.showScreen2 = true;
    //     }
    // }

    // handlePrevious() {
    //     console.log('Parent: Received previous event from child');
    //     this.showScreen1 = true;
    //     this.showScreen2 = false;
    // }

    @track showScreen1 = true;
    @track showScreen2 = false;
    @track leadId;

    @track value = null;
    @track options = [];

    get disableNext() {
        return !this.value;
    }

    @wire(getProjectQuotationTypeValues)
    wiredValues({ data, error }) {
        if (data) {
            this.options = data.map((label, index) => ({
                label,
                value: label,
                cssClass: `radio-row animate-stagger stagger-${index}`,
                selected: false
            }));
        } else if (error) {
            console.error('Error loading picklist values', error);
        }
    }

    handleChange(event) {
        this.value = event.target.value;

        this.options = this.options.map(opt => ({
            ...opt,
            selected: opt.value === this.value
        }));
    }

    handleRipple(event) {
        const ripple = event.currentTarget.querySelector('.ripple');
        if (ripple) {
            ripple.classList.remove('run');
            void ripple.offsetWidth;
            ripple.classList.add('run');
        }
    }

    goNext() {
        console.log('Next clicked. Selected value:', this.value);

        // Extract Lead Id from URL
        const urlParams = new URLSearchParams(window.location.search);
        this.leadId = urlParams.get('id');
        console.log('Lead ID from URL:', this.leadId);

        // 🔥 UPDATE THE PICKLIST IN LEAD RECORD BEFORE GOING TO SCREEN 2
        updateQuotationType({
            leadId: this.leadId,
            quotationType: this.value
        })
        .then(() => {
            console.log('Quotation type updated successfully ✔');

            // Only show screen 2 if Manual
            if (this.value === 'Manual Quotation') {
                this.showScreen1 = false;
                this.showScreen2 = true;
            } else {
                // If Automatic, show message or redirect
                console.log('Automatic quotation selected — you can add redirect or message');
            }
        })
        .catch(error => {
            console.error('Error updating quotation type:', error);
        });
    }

    handlePrevious() {
        console.log('Parent: Received previous event from child');
        this.showScreen1 = true;
        this.showScreen2 = false;
    }
}