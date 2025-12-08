import { LightningElement, api, track, wire } from 'lwc';
import getLeadById
    from '@salesforce/apex/Arelia_ManualProjectRequestController.getLeadById';
import getTypeOfProjectPicklistValues
    from '@salesforce/apex/Arelia_ManualProjectRequestController.getTypeOfProjectPicklistValues';
import updateLead
    from '@salesforce/apex/Arelia_ManualProjectRequestController.updateLead';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Arelia_Site_Label from '@salesforce/label/c.Arelia_Site_Label';


export default class AreliaManualProjectRequestComp extends LightningElement {
    @api leadId;
    @api quotationType;

    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track company = '';
    @track budget = '';
    @track siteLocation = '';
    @track projectDescription = '';
    @track typeOfProject = '';
    @track projectScope = '';
    @track projectScopeOptions = [];
    @track projectTypeOptions = [];
    @track showForm = true;
    @track showSuccess = false;
    @track countryCode = '+91';
    @track phoneNumber = '';

    hasLoaded = false;

    // Static dependency map as you requested
    scopeMap = {
        Home: [
            { label: 'Full Home Interiors', value: 'Full Home Interiors' },
            { label: 'Home Decor', value: 'Home Decor' },
            { label: 'Kitchen', value: 'Kitchen' },
            { label: 'Bed Room', value: 'Bed Room' },
            { label: 'Hall Interior', value: 'Hall Interior' }
        ],
        Office: [
            { label: 'Conference Hall', value: 'Conference Hall' },
            { label: 'Fully Office Interiors', value: 'Fully Office Interiors' },
            { label: 'Office Decor', value: 'Office Decor' },
            { label: 'Office Space', value: 'Office Space' },
            { label: 'Dining Hall', value: 'Dining Hall' },
            { label: 'Cabins', value: 'Cabins' }
        ],
        'Only Project Plan': []
    };

    countryOptions = [
        { label: '+91 (India)', value: '+91' },
        { label: '+1 (USA)', value: '+1' },
        { label: '+44 (UK)', value: '+44' },
        { label: '+971 (UAE)', value: '+971' }
    ];

    // 🔹 Dynamic Type_Of_Project__c picklist
    @wire(getTypeOfProjectPicklistValues)
    wiredTypePicklist({ data, error }) {
        if (data) {
            this.projectTypeOptions = data.map((label) => ({
                label,
                value: label
            }));

            // If Lead already has a type, ensure scope options are in sync
            if (this.typeOfProject) {
                this.projectScopeOptions = this.scopeMap[this.typeOfProject] || [];
            }
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading Type_Of_Project__c picklist', error);
        }
    }

    // Load lead only once when leadId is set
    renderedCallback() {
        if (!this.leadId || this.hasLoaded) {
            return;
        }
        this.hasLoaded = true;
        this.loadLeadDetails();
    }

    loadLeadDetails() {
        getLeadById({ leadId: this.leadId })
            .then((result) => {
                if (!result) {
                    return;
                }

                this.firstName = result.FirstName || '';
                this.lastName = result.LastName || '';
                this.email = result.Email || '';
                this.phone = result.Phone || '';
                this.company = result.Company || '';
                this.budget = result.Customer_Budget__c || '';
                this.typeOfProject = result.Type_Of_Project__c || '';
                this.projectScope = result.Project_Scope__c || '';
                this.projectDescription = result.Project_Description__c || '';
                this.siteLocation = result.Site_Location__c || '';

                // Split phone into countryCode + number if possible
                if (this.phone) {
                    const match = this.phone.match(/^(\+\d+)\s?(.*)/);
                    if (match) {
                        this.countryCode = match[1];
                        this.phoneNumber = match[2];
                    } else {
                        this.countryCode = '+91';
                        this.phoneNumber = this.phone;
                    }
                }

                // If type already has a value, set scope options from static map
                if (this.typeOfProject) {
                    this.projectScopeOptions = this.scopeMap[this.typeOfProject] || [];
                }
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error loading Lead from Apex', error);
            });
    }

    handleChange(event) {
        const { name, value } = event.target;
        this[name] = value;

        if (name === 'typeOfProject') {
            this.projectScopeOptions = this.scopeMap[value] || [];
            this.projectScope = '';
        }
    }

    handleCountryChange(event) {
        this.countryCode = event.detail.value;
        this.updatePhone();
    }

    handlePhoneInput(event) {
        this.phoneNumber = event.target.value;
        this.updatePhone();
    }

    updatePhone() {
        this.phone = `${this.countryCode} ${this.phoneNumber}`.trim();
    }

    get isScopeDisabled() {
        return this.projectScopeOptions.length === 0;
    }

    submitLead() {
        if (!this.leadId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Lead',
                    message:
                        'Lead Id is not available. Please open this page from a valid project link.',
                    variant: 'error'
                })
            );
            return;
        }

        const numericBudget =
            this.budget && this.budget !== '' ? parseFloat(this.budget) : null;

        const payload = {
            leadId: this.leadId,
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            typeOfProject: this.typeOfProject,
            projectScope: this.projectScope,
            company: this.company,
            budget: numericBudget,
            projectDescription: this.projectDescription,
            siteLocation: this.siteLocation,
            quotationType: this.quotationType // from parent (Manual / Automatic)
        };

        updateLead({ payload })
            .then(() => {
                this.showForm = false;
                this.showSuccess = true;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Request Submitted',
                        message: 'Your project request has been updated successfully.',
                        variant: 'success'
                    })
                );
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error updating Lead', error);

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message:
                            error && error.body && error.body.message
                                ? error.body.message
                                : 'Unable to submit project request.',
                        variant: 'error'
                    })
                );
            });

    }

    handleCloseSuccess() {
        // this.showSuccess = false;
        // this.showForm = true;
        window.location.href = Arelia_Site_Label;
    }


    goToPrevious() {
        this.dispatchEvent(new CustomEvent('previous'));
    }
}
