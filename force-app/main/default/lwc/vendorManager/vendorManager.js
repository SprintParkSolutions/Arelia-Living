import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getFieldSetFields from '@salesforce/apex/VendorOpportunityController.getFieldSetFields';
import hasExistingRecords from '@salesforce/apex/VendorOpportunityController.hasExistingRecords';
import createVendorOpportunities from '@salesforce/apex/VendorOpportunityController.createVendorOpportunities';
import getExistingRecords from '@salesforce/apex/VendorOpportunityController.getExistingRecords';
import reparentFiles from '@salesforce/apex/VendorOpportunityController.reparentFiles';
import getAttachedFileNames from '@salesforce/apex/VendorOpportunityController.getAttachedFileNames';

export default class VendorManager extends LightningElement {
    @api recordId;
    @track isLoading = true;

    // View States
    showLanding = false;
    showCreation = false;
    showPreview = false;

    // PATH INDICATOR STATE
    @track currentStep = 'start'; 

    // Data Config
    createFields = [];
    previewFieldSet = [];
    
    // Data Storage
    @track rows = [];
    @track previewData = [];

    connectedCallback() {
        this.init();
    }

    async init() {
        try {
            // 1. Fetch Field Sets
            const cFields = await getFieldSetFields({ objectName: 'Vendor_Opportunity__c', fieldSetName: 'Creation_Field_Set' });
            this.createFields = cFields.map(f => ({
                ...f,
                isOppField: (f.fieldPath === 'Opportunity__c') 
            }));

            const pFields = await getFieldSetFields({ objectName: 'Vendor_Opportunity__c', fieldSetName: 'Preview_Fieldset' });
            const createFieldNames = new Set(this.createFields.map(f => f.fieldPath));
            this.previewFieldSet = pFields.map(f => ({
                ...f,
                isEditable: createFieldNames.has(f.fieldPath)
            }));

            // 2. Check Existance & Set Initial Step
            const exists = await hasExistingRecords({ opportunityId: this.recordId });
            if (exists) {
                this.showLanding = true;
                this.currentStep = 'start';
            } else {
                this.initCreation();
            }
        } catch (error) {
            this.showToast('Error', 'Init failed: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // --- CREATION ---
    initCreation() {
        this.showCreation = true;
        this.currentStep = 'draft'; // Update Path
        this.addRow();
    }

    // NEW: Handle user clicking "Add New Record" from the Preview Screen
    handleAddNewFromPreview() {
        this.rows = []; // Reset rows
        this.addRow(); // Add one blank row
        this.showPreview = false;
        this.showCreation = true;
        this.currentStep = 'draft'; // Move path back
    }

    addRow() {
        this.rows.push({
            key: Date.now(),
            displayIndex: this.rows.length + 1, // Serial Number for Creation
            data: {}, 
            uploadedDocId: null,
            fileName: null
        });
    }

    deleteRow(event) {
        const index = event.currentTarget.dataset.index;
        if(this.rows.length > 1) {
            this.rows.splice(index, 1);
            this.rows = this.rows.map((r, i) => ({ ...r, displayIndex: i + 1 })); // Re-calculate Serial Numbers
        }
    }

    get isMultipleRows() { return this.rows.length > 1; }

    handleFieldChange(event) {
        const index = event.target.dataset.rowIndex;
        const fieldName = event.target.fieldName;
        this.rows[index].data[fieldName] = event.target.value;
    }

    handleUploadFinished(event) {
        const index = event.target.dataset.rowIndex;
        const files = event.detail.files;
        if(files.length > 0) {
            this.rows[index].uploadedDocId = files[0].documentId;
            this.rows[index].fileName = files[0].name;
            this.showToast('Success', 'Quotation uploaded', 'success');
        }
    }

    async handleCreate() {
        this.isLoading = true;
        try {
            // 1. Prepare records for Apex
            const recordsToInsert = this.rows.map(r => ({
                ...r.data,
                sobjectType: 'Vendor_Opportunity__c'
            }));

            // 2. Insert Records
            const savedRecords = await createVendorOpportunities({ 
                records: recordsToInsert, 
                opportunityId: this.recordId 
            });

            // 3. Link Files (Reparent from Opp -> New Record)
            const fileMap = {}; 
            this.rows.forEach((row, index) => {
                // Only map if we have a file AND a valid saved record
                if(row.uploadedDocId && savedRecords[index] && savedRecords[index].Id) {
                    fileMap[row.uploadedDocId] = savedRecords[index].Id;
                }
            });

            // Only call Apex if we actually have files to move
            if(Object.keys(fileMap).length > 0) {
                await reparentFiles({ fileMap: fileMap });
            }

            // 4. Success & Transition
            this.showToast('Success', 'Records created and files attached.', 'success');
            this.showCreation = false;
            this.goToPreview(); 

        } catch (error) {
            // UPDATED ERROR HANDLING: Catches "pageErrors" (common in DML) to avoid "undefined"
            let msg = 'Unknown Error';
            if (error.body) {
                if (error.body.message) msg = error.body.message;
                else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    msg = error.body.pageErrors[0].message;
                }
            } else if (error.message) {
                msg = error.message;
            }
            this.showToast('Error', 'Creation failed: ' + msg, 'error');
            console.error('Full Error Details:', JSON.parse(JSON.stringify(error)));
        } finally {
            this.isLoading = false;
        }
    }

    // --- PREVIEW ---
    async goToPreview() {
        this.isLoading = true;
        this.showLanding = false;
        this.showCreation = false; // Ensure creation is hidden if coming from Back button
        this.showPreview = true;
        this.currentStep = 'review';
        
        try {
            // 1. Get Records
            const fieldsToQuery = this.previewFieldSet.map(f => f.fieldPath);
            const data = await getExistingRecords({ 
                opportunityId: this.recordId, 
                queryFields: fieldsToQuery 
            });

            // 2. Get File Names for these records
            const recordIds = data.map(r => r.Id);
            const fileMap = await getAttachedFileNames({ parentIds: recordIds });

            // 3. Merge Data (Add Serial No + File Name + Button Label)
            this.previewData = data.map((record, index) => {
                const fileName = fileMap[record.Id]; 
                return {
                    ...record,
                    serialNumber: index + 1,
                    existingFileName: fileName || null, // logic to show file name
                    uploadLabel: fileName ? 'Replace File' : 'Upload Quotation' // Dynamic label
                };
            });

        } catch (error) {
            this.showToast('Error', 'Could not load preview: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePreviewUpload(event) {
        const files = event.detail.files;
        const recordId = event.target.dataset.id; // Get the specific record ID

        if(files.length > 0) {
            const newFileName = files[0].name;
            
            // Update the UI immediately to show the new file
            this.previewData = this.previewData.map(rec => {
                if(rec.Id === recordId) {
                    return { 
                        ...rec, 
                        existingFileName: newFileName, 
                        uploadLabel: 'Replace File' 
                    };
                }
                return rec;
            });

            this.showToast('Success', 'File updated successfully', 'success');
        }
    }

    async handleFinalSave() {
        this.isLoading = true;
        const forms = this.template.querySelectorAll('lightning-record-edit-form');
        const submitPromises = [];

        forms.forEach(form => {
            const p = new Promise((resolve, reject) => {
                // Define cleanup FIRST
                let handleSuccess;
                let handleError;

                const cleanup = () => {
                    form.removeEventListener('success', handleSuccess);
                    form.removeEventListener('error', handleError);
                };

                handleSuccess = () => {
                    cleanup();
                    resolve('success');
                };

                handleError = (errorPayload) => {
                    cleanup();
                    reject(errorPayload);
                };
                
                form.addEventListener('success', handleSuccess);
                form.addEventListener('error', handleError);
                form.submit();
            });
            submitPromises.push(p);
        });

        try {
            await Promise.all(submitPromises);
            this.showToast('Success', 'All records saved successfully!', 'success');
            this.closeAction();
        } catch (error) {
            this.showToast('Error', 'Some records failed to save: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}