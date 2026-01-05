import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import createVendorAssignments
    from '@salesforce/apex/VendorAssignmentController.createVendorAssignments';

export default class VendorAssignmentManager extends LightningElement {

    @api recordId;
    @track isLoading = false;
    @track rows = [];

    connectedCallback() {
        this.addRow();
    }

    get isReadyToRender() {
        return true;
    }

    addRow() {
        this.rows = [
            ...this.rows,
            {
                key: Date.now(),
                data: {}
            }
        ];
    }

    handleOpportunityChange(event) {
        const index = event.target.dataset.rowIndex;
        this.rows[index].data.Opportunity__c = event.target.value;
    }

    async handleCreate() {
        this.isLoading = true;

        try {
            const payload = this.rows.map(r => ({
                ...r.data,
                Project__c: this.recordId,
                sobjectType: 'Vendor_Assignment__c'
            }));

            await createVendorAssignments({
                records: payload,
                projectId: this.recordId
            });

            this.showToast('Success', 'Vendor Assignments created', 'success');
            this.closeAction();

        } catch (e) {
            this.showToast('Error', e.body?.message || e.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}
