import { LightningElement, track, wire } from 'lwc';
import getProjectQuotationTypeValues
    from '@salesforce/apex/ProjectRequestController.getProjectQuotationTypeValues';

export default class ProjectRequestCodeComponent extends LightningElement {
    @track showScreen1 = true;
    @track showManualScreen = false;
    @track showAutomaticScreen = false;

    @track leadId;
    @track value = null; // selected quotation type
    @track options = [];

    connectedCallback() {
        const urlParams = new URLSearchParams(window.location.search);
        this.leadId = urlParams.get('id');
    }

    get disableNext() {
        return !this.value;
    }

    @wire(getProjectQuotationTypeValues)
    wiredValues({ data, error }) {
        if (data) {
            this.options = data.map((label, index) => ({
                label,
                value: label,
                selected: this.value === label,
                cssClass: this.buildRowClass(label, index)
            }));
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading picklist values', error);
        }
    }

    buildRowClass(label, index) {
        const base = 'radio-row animate-stagger stagger-' + index;
        const selectedClass = this.value === label ? ' radio-row_selected' : '';
        return base + selectedClass;
    }

    handleChange(event) {
        const selectedValue = event.target.value;
        this.setSelectedValue(selectedValue);
    }

    handleRowClick(event) {
        const rowValue = event.currentTarget.dataset.value;
        if (rowValue) {
            this.setSelectedValue(rowValue);
        }
    }

    setSelectedValue(selectedValue) {
        this.value = selectedValue;
        this.options = this.options.map((opt, index) => ({
            ...opt,
            selected: opt.value === this.value,
            cssClass: this.buildRowClass(opt.value, index)
        }));
    }

    goNext() {
        if (!this.value || !this.leadId) {
            return;
        }

        this.showScreen1 = false;
        this.showManualScreen = false;
        this.showAutomaticScreen = false;

        // You can adjust these string checks to match your picklist labels
        if (this.value === 'Manual Quotation') {
            this.showManualScreen = true;
        } else if (this.value === 'Automatic Quotation') {
            this.showAutomaticScreen = true;
        } else {
            // If you add more quotation types later, you can handle them here
            this.showManualScreen = true;
        }
    }

    handlePrevious() {
        this.showScreen1 = true;
        this.showManualScreen = false;
        this.showAutomaticScreen = false;
    }
}
