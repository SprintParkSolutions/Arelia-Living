import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import createTasks from '@salesforce/apex/TaskBulkController.createTasks';

// Import field to get OwnerId from Vendor Assignment
import OWNER_ID_FIELD from '@salesforce/schema/Vendor_Assignment__c.OwnerId'; 

// ** IMPORTANT: Replace 'Vendor_Assignment__c' with the actual API Name of your object **

export default class VendorTaskCreator extends LightningElement {
    @api recordId; // The ID of the Vendor Assignment Record
    @track taskList = []; 
    @track isSaving = false;

    // Default Status Options
    get statusOptions() {
        return [
            { label: 'Not Started', value: 'Not Started' },
            { label: 'In Progress', value: 'In Progress' },
            { label: 'Completed', value: 'Completed' },
            { label: 'Waiting on someone else', value: 'Waiting on someone else' },
            { label: 'Deferred', value: 'Deferred' }
        ];
    }

    // Fetch the OwnerId of the current Vendor Assignment record
    @wire(getRecord, { recordId: '$recordId', fields: [OWNER_ID_FIELD] })
    vendorRecord;

    get vendorOwnerId() {
        return getFieldValue(this.vendorRecord.data, OWNER_ID_FIELD);
    }

    get isMoreThanOneRow() {
        return this.taskList.length > 1;
    }

    connectedCallback() {
        // Initialize with one empty row
        this.addNewRow();
    }

    // Add a new blank task object to the list
    addNewRow() {
        this.taskList.push({
            key: Date.now(), // Unique key for UI iteration
            index: this.taskList.length + 1,
            Subject: '',
            Status: 'Not Started',
            Start_Date__c: null,
            ActivityDate: null,
            Assigned_Percentage__c: null
        });
    }

    // Remove a specific row
    removeRow(event) {
        if (this.taskList.length > 1) {
            const indexToRemove = event.target.dataset.index;
            this.taskList.splice(indexToRemove, 1);
            // Re-index for display purposes
            this.taskList.forEach((task, idx) => { task.index = idx + 1; });
        }
    }

    // Handle input changes for any field in any row
    handleInputChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.dataset.field;
        const value = event.target.value;

        this.taskList[index][field] = value;
    }

    handleSave() {
        // Basic Validation: Check if Subject is filled
        const allValid = [...this.template.querySelectorAll('lightning-input')]
            .reduce((validSoFar, inputCmp) => {
                inputCmp.reportValidity();
                return validSoFar && inputCmp.checkValidity();
            }, true);

        if (!allValid) {
            this.showToast('Error', 'Please complete all required fields.', 'error');
            return;
        }

        if (!this.vendorOwnerId) {
            this.showToast('Error', 'Could not fetch Vendor Assignment Owner. Please refresh and try again.', 'error');
            return;
        }

        this.isSaving = true;

        // Map UI data to Salesforce Task Objects
        const tasksToInsert = this.taskList.map(row => {
            return {
                sobjectType: 'Task',
                WhatId: this.recordId,       // Parent Vendor Assignment ID
                OwnerId: this.vendorOwnerId, // Parent Vendor Owner ID
                Subject: row.Subject,
                Status: row.Status,
                Start_Date__c: row.Start_Date__c,
                ActivityDate: row.ActivityDate,
                Assigned_Percentage__c: row.Assigned_Percentage__c
            };
        });

        // Call Apex
        createTasks({ newTasks: tasksToInsert })
            .then(() => {
                this.showToast('Success', 'Tasks created successfully', 'success');
                this.closeAction();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                this.isSaving = false;
            });
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}