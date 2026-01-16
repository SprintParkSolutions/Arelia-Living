import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getRelatedImages from '@salesforce/apex/ImageApprovalController.getRelatedImages';
import sendApprovalRequest from '@salesforce/apex/ImageApprovalController.sendApprovalRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DesignUpload extends LightningElement {
    @api recordId;
    @track files = [];
    @track uploadedFileId = null;
    wiredFilesResult;
    isLoading = false;

    get acceptedFormats() { return ['.pdf', '.png', '.jpg', '.jpeg']; }

    @wire(getRelatedImages, { recordId: '$recordId' })
    wiredFiles(result) {
        this.wiredFilesResult = result;
        if (result.data) {
            this.files = result.data;
        }
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if(uploadedFiles && uploadedFiles.length > 0) {
            this.uploadedFileId = uploadedFiles[0].documentId;
            this.showToast('Success', 'File Uploaded Successfully', 'success');
            refreshApex(this.wiredFilesResult);
        }
    }

    handleSendClick() {
        if(!this.uploadedFileId) return;
        this.isLoading = true;

        sendApprovalRequest({ recordId: this.recordId, fileId: this.uploadedFileId })
            .then(() => {
                this.showToast('Success', 'Approval Request Sent', 'success');
                this.uploadedFileId = null; 
                return refreshApex(this.wiredFilesResult);
            })
            .catch(error => {
                let message = error.body ? error.body.message : 'Unknown Error';
                this.showToast('Error', message, 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}