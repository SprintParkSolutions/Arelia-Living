import { LightningElement, track, wire } from 'lwc';
import getProjectQuotationTypeValues from '@salesforce/apex/ProjectRequestController.getProjectQuotationTypeValues';

export default class ProjectRequestCodeComponent extends LightningElement {
        @track value = null;
        @track options = [];
    
        @wire(getProjectQuotationTypeValues)
        wiredValues({ data, error }) {
            if (data) {
                // Precompute full CSS class and selected property for each option
                this.options = data.map((label, index) => {
                    return {
                        label,
                        value: label,
                        cssClass: `radio-row animate-stagger stagger-${index}`,
                        selected: false
                    };
                });
            } else if (error) {
                console.error('Error loading picklist values', error);
            }
        }
    
        handleChange(event) {
            this.value = event.target.value;
    
            // Update selected property for each option
            this.options = this.options.map(opt => {
                return { ...opt, selected: opt.value === this.value };
            });
    
            this.dispatchEvent(
                new CustomEvent('quotetypechange', { detail: this.value })
            );
        }
    
        handleRipple(event) {
            const ripple = event.currentTarget.querySelector('.ripple');
            if (ripple) {
                ripple.classList.remove('run');
                void ripple.offsetWidth; // restart animation
                ripple.classList.add('run');
            }
        }
}