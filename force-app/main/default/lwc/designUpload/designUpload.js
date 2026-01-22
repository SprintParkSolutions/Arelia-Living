import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getRelatedImages from '@salesforce/apex/ImageApprovalController.getRelatedImages';
import sendApprovalRequest from '@salesforce/apex/ImageApprovalController.sendApprovalRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DesignUpload extends LightningElement {
    @api recordId;
    @track latestFile = null;
    wiredImagesResult;
    isLoading = false;

    get acceptedFormats() { return ['.pdf', '.png', '.jpg', '.jpeg']; }

    @wire(getRelatedImages, { recordId: '$recordId' })
    wiredImages(result) {
        this.wiredImagesResult = result;
        if (result.data && result.data.length > 0) {
            const img = result.data[0];
            let badgeClass = 'slds-badge slds-m-top_small ';
            if(img.status === 'Approved') badgeClass += 'slds-theme_success';
            else if(img.status === 'Sent') badgeClass += 'slds-theme_warning';
            else badgeClass += 'slds-theme_inverse';

            this.latestFile = {
                ...img,
                isPdf: img.extension === 'pdf',
                status: img.status || 'Pending',
                statusClass: badgeClass
            };
        }
    }

    handleUploadFinished() {
        this.showToast('Success', 'File Uploaded', 'success');
        refreshApex(this.wiredImagesResult);
    }

    handleSendClick() {
        if(!this.latestFile) return;
        this.isLoading = true;
        sendApprovalRequest({ recordId: this.recordId, fileId: this.latestFile.id })
            .then(() => {
                this.showToast('Success', 'Email Sent', 'success');
                this.latestFile = { ...this.latestFile, status: 'Sent' };
            })
            .catch(error => {
                let message = error.body ? error.body.message : 'Unknown Error';
                this.showToast('Error', message, 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleReset() { this.latestFile = null; }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}