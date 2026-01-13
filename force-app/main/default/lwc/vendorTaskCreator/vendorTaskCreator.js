import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

// Apex
import createTasks from '@salesforce/apex/TaskBulkController.createTasks';
import updateTasks from '@salesforce/apex/TaskBulkController.updateTasks';
import hasExistingTasks from '@salesforce/apex/TaskBulkController.hasExistingTasks';
import getExistingTasks from '@salesforce/apex/TaskBulkController.getExistingTasks';
import getTaskFiles from '@salesforce/apex/TaskBulkController.getTaskFiles';

import OWNER_ID_FIELD from '@salesforce/schema/Vendor_Assignment__c.OwnerId'; 

export default class VendorTaskCreator extends LightningElement {
    @api recordId;
    @track isLoading = true;
    
    showLanding = false;
    showCreation = false;
    showPreview = false;
    @track currentStep = 'start'; 

    @track taskList = []; 
    @track previewData = [];

    @wire(getRecord, { recordId: '$recordId', fields: [OWNER_ID_FIELD] })
    vendorRecord;

    get vendorOwnerId() { return getFieldValue(this.vendorRecord.data, OWNER_ID_FIELD); }

    get statusOptions() {
        return [
            { label: 'Not Started', value: 'Not Started' },
            { label: 'In Progress', value: 'In Progress' },
            { label: 'Completed', value: 'Completed' },
            { label: 'Waiting on someone else', value: 'Waiting on someone else' },
            { label: 'Deferred', value: 'Deferred' }
        ];
    }

    connectedCallback() { this.init(); }

    async init() {
        try {
            const exists = await hasExistingTasks({ parentId: this.recordId });
            if (exists) {
                this.showLanding = true;
                this.currentStep = 'start';
            } else {
                this.initCreation();
            }
        } catch (error) {
            console.error('Init Error', error);
            this.showToast('Error', 'Init failed', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    initCreation() {
        this.showLanding = false;
        this.showPreview = false;
        this.showCreation = true;
        this.currentStep = 'draft';
        if(this.taskList.length === 0) this.addNewRow();
    }

    addNewRow() {
        this.taskList.push({
            key: Date.now(),
            displayIndex: this.taskList.length + 1,
            Subject: '', Status: 'Not Started', Start_Date__c: null, ActivityDate: null, Assigned_Percentage__c: null
        });
    }

    removeRow(event) {
        if (this.taskList.length > 1) {
            this.taskList.splice(event.target.dataset.index, 1);
            this.taskList.forEach((task, idx) => { task.displayIndex = idx + 1; });
        }
    }

    get isMoreThanOneRow() { return this.taskList.length > 1; }

    handleInputChange(event) {
        this.taskList[event.target.dataset.index][event.target.dataset.field] = event.target.value;
    }

    handleCreateAndProceed() {
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox')]
            .reduce((validSoFar, inputCmp) => { inputCmp.reportValidity(); return validSoFar && inputCmp.checkValidity(); }, true);

        if (!allValid) return;

        this.isLoading = true;
        const tasksToInsert = this.taskList.map(row => ({
            sobjectType: 'Task',
            WhatId: this.recordId,
            OwnerId: this.vendorOwnerId,
            Subject: row.Subject,
            Status: row.Status,
            Start_Date__c: row.Start_Date__c,
            ActivityDate: row.ActivityDate,
            Assigned_Percentage__c: row.Assigned_Percentage__c
        }));

        createTasks({ newTasks: tasksToInsert })
            .then(() => {
                this.showToast('Success', 'Tasks created.', 'success');
                this.taskList = [];
                this.goToPreview();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                this.isLoading = false;
            });
    }

    // --- UPDATED PREVIEW LOGIC FOR MULTIPLE FILES ---
    async goToPreview() {
        this.isLoading = true;
        this.showLanding = false;
        this.showCreation = false;
        this.showPreview = true;
        this.currentStep = 'review';

        try {
            const tasks = await getExistingTasks({ parentId: this.recordId });
            const taskIds = tasks.map(t => t.Id);
            
            // Fetch returns Map<Id, List<FileData>>
            const fileMap = await getTaskFiles({ parentIds: taskIds });

            this.previewData = tasks.map((t, index) => {
                // Get the raw list from Apex, default to empty array if none
                const rawFiles = fileMap[t.Id] || [];
                
                // Process the list into UI-friendly objects with Image URLs
                const processedFileList = rawFiles.map(fd => ({
                    key: fd.documentId, // Unique key for iteration
                    fileName: fd.fileName,
                    // Standard Salesforce Image Preview URL
                    imageUrl: `/sfc/servlet.shepherd/version/download/${fd.versionId}`
                }));

                return {
                    Id: t.Id,
                    Subject: t.Subject || t.subject,
                    Status: t.Status || t.status,
                    Start_Date__c: t.Start_Date__c || t.start_date__c,
                    ActivityDate: t.ActivityDate || t.activitydate,
                    Assigned_Percentage__c: t.Assigned_Percentage__c || t.assigned_percentage__c,
                    serialNumber: index + 1,
                    
                    // New Array property to hold multiple files
                    fileList: processedFileList,
                    hasFiles: processedFileList.length > 0
                };
            });

        } catch (error) {
            console.error(error);
            this.showToast('Error', 'Could not load preview', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePreviewChange(event) {
        this.previewData[event.target.dataset.index][event.target.dataset.field] = event.target.value;
    }

    handlePreviewUpload(event) {
        const files = event.detail.files;
        if (files.length > 0) {
            // We just reload the whole preview. Apex will fetch the new complete list.
            this.showToast('Success', 'Files uploaded.', 'success');
            this.goToPreview(); 
        }
    }

    handleFinalSave() {
        this.isLoading = true;
        const recordsToUpdate = this.previewData.map(row => ({
            Id: row.Id,
            Subject: row.Subject,
            Status: row.Status,
            Start_Date__c: row.Start_Date__c,
            ActivityDate: row.ActivityDate,
            Assigned_Percentage__c: row.Assigned_Percentage__c
        }));

        updateTasks({ tasksToUpdate: recordsToUpdate })
            .then(() => {
                this.showToast('Success', 'All records saved!', 'success');
                this.closeAction();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                this.isLoading = false;
            });
    }

    closeAction() { this.dispatchEvent(new CloseActionScreenEvent()); }
    showToast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
}