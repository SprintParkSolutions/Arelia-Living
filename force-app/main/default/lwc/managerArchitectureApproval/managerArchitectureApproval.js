import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getDesignById from '@salesforce/apex/ManagerApprovalController.getDesignById';
import submitManagerDecision from '@salesforce/apex/ManagerApprovalController.submitManagerDecision';

export default class ManagerArchitectureApproval extends LightningElement {
    @track designData;
    recordId; 
    error;
    
    comments = '';
    showCommentBox = false;
    isFinalized = false;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.id; 
            console.log('Manager Page Loaded. Record ID:', this.recordId); // DEBUG

            if (this.recordId) {
                this.loadData();
            } else {
                this.error = 'Invalid Link: Record ID missing.';
            }
        }
    }

    loadData() {
        getDesignById({ recordId: this.recordId }) 
            .then(data => {
                console.log('Design Data Loaded:', JSON.stringify(data)); // DEBUG
                this.designData = data;
                if(data.status === 'Approved') {
                    this.isFinalized = true;
                }
            })
            .catch(err => {
                console.error('Load Error:', err);
                this.error = 'Invalid Link or Record not found.';
            });
    }

    get statusBadgeClass() {
        return this.designData && this.designData.status === 'Approved' 
            ? 'slds-badge slds-theme_success' 
            : 'slds-badge slds-theme_warning';
    }

    handleApprove() { this.submit('Approve'); }
    
    toggleComments() { this.showCommentBox = !this.showCommentBox; }
    
    handleCommentChange(event) { this.comments = event.target.value; }

    handleSubmitRejection() {
        if(!this.comments) {
            const inputField = this.template.querySelector('lightning-textarea');
            inputField.setCustomValidity('Please provide a reason.');
            inputField.reportValidity();
            return;
        }
        this.submit('Reject');
    }

    submit(action) {
        this.error = null;
        console.log(`Submitting Action: ${action} for ID: ${this.recordId}`); // DEBUG

        // FIX: Ensure 'recordId' key matches Apex parameter name
        submitManagerDecision({ recordId: this.recordId, action: action, comments: this.comments })
            .then(() => {
                console.log('Submit Success'); // DEBUG
                this.isFinalized = true;
                this.designData = { 
                    ...this.designData, 
                    status: action === 'Approve' ? 'Approved' : 'Rejected', 
                    comments: this.comments 
                };
            })
            .catch(err => {
                console.error('Submit Error:', err);
                // Extract error message safely
                let msg = 'Error submitting decision.';
                if (err.body && err.body.message) msg = err.body.message;
                this.error = msg;
            });
    }
}