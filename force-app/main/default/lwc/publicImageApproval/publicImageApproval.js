import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getFileByToken from '@salesforce/apex/ImageApprovalController.getFileByToken';
import submitDecision from '@salesforce/apex/ImageApprovalController.submitDecision';

export default class PublicImageApproval extends LightningElement {
    @track fileData;
    token;
    error;
    comments = '';
    showCommentBox = false;
    isFinalized = false;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.token = currentPageReference.state.token;
            if (this.token) {
                this.loadData();
            } else {
                this.error = 'Invalid Link: Token missing.';
            }
        }
    }

    loadData() {
        getFileByToken({ token: this.token, versionId: null })
            .then(data => {
                this.fileData = data;
                if(data.status === 'Approved' || data.status === 'Changes Requested') {
                    this.isFinalized = true;
                }
            })
            .catch(err => {
                console.error(err);
                this.error = 'Invalid Link or Record not found.';
            });
    }

    get statusBadgeClass() {
        if(this.fileData.status === 'Approved') return 'slds-badge slds-theme_success';
        if(this.fileData.status === 'Changes Requested') return 'slds-badge slds-theme_error';
        return 'slds-badge';
    }

    handleApprove() { this.submit('Approved'); }
    toggleComments() { this.showCommentBox = !this.showCommentBox; }
    handleCommentChange(event) { this.comments = event.target.value; }

    handleSubmitChanges() {
        if(!this.comments) {
            const inputField = this.template.querySelector('lightning-textarea');
            inputField.setCustomValidity('Comments required.');
            inputField.reportValidity();
            return;
        }
        this.submit('Changes Requested');
    }

    submit(status) {
        this.error = null;
        submitDecision({ token: this.token, versionId: null, status: status, comments: this.comments })
            .then(() => {
                this.isFinalized = true;
                this.fileData = { ...this.fileData, status: status, comments: this.comments };
            })
            .catch(err => {
                // FIX: Log the error to satisfy ESLint
                console.error('Submit Error:', err);
                this.error = 'Error submitting response. Please try again.';
            });
    }
}