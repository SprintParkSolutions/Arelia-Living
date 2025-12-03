import { LightningElement, api, track } from 'lwc';
import getLeadById from '@salesforce/apex/Arelia_ManualProjectRequestController.getLeadById';
import updateLead from '@salesforce/apex/Arelia_ManualProjectRequestController.updateLead';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AreliaManualProjectRequestComp extends LightningElement {
    @api leadId; // Receive leadId from parent
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
    @track showForm = true;
    @track showSuccess = false;
    @track countryCode = '+91';
    @track phoneNumber = '';

    projectTypeOptions = [
        { label: 'Home', value: 'Home' },
        { label: 'Office', value: 'Office' },
        { label: 'Only Project Plan', value: 'Only Project Plan' },
        { label: 'Other', value: 'Other' }
    ];

    countryOptions = [
        { label: '🇮🇳 +91 (India)', value: '+91' },
        { label: '🇺🇸 +1 (USA)', value: '+1' },
        { label: '🇬🇧 +44 (UK)', value: '+44' },
        { label: '🇦🇪 +971 (UAE)', value: '+971' }
    ];

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

    // Load lead details whenever leadId is set
    renderedCallback() {
        if (this.leadId && !this.hasLoaded) {
            console.log('renderedCallback: leadId received ->', this.leadId);
            this.loadLeadDetails();
            this.hasLoaded = true;
        }
    }

    loadLeadDetails() {
        console.log('loadLeadDetails called with leadId ->', this.leadId);

        getLeadById({ leadId: this.leadId })
            .then(result => {
                console.log('Lead data received from Apex ->', result);

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

                // Extract country code and phone number
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

                if (this.typeOfProject) {
                    this.projectScopeOptions = this.scopeMap[this.typeOfProject] || [];
                }
            })
            .catch(error => {
                console.error('Error loading Lead from Apex ->', error);
            });
    }

    handleChange(event) {
        const { name, value } = event.target;
        console.log(`handleChange: ${name} ->`, value);
        this[name] = value;

        if (name === 'typeOfProject') {
            this.projectScopeOptions = this.scopeMap[value] || [];
            this.projectScope = '';
        }
    }

    handleCountryChange(event) {
        console.log('handleCountryChange ->', event.detail.value);
        this.countryCode = event.detail.value;
        this.updatePhone();
    }

    handlePhoneInput(event) {
        console.log('handlePhoneInput ->', event.target.value);
        this.phoneNumber = event.target.value;
        this.updatePhone();
    }

    updatePhone() {
        this.phone = `${this.countryCode} ${this.phoneNumber}`.trim();
        console.log('updatePhone ->', this.phone);
    }

    get isScopeDisabled() {
        return this.projectScopeOptions.length === 0;
    }

    submitLead() {
        console.log('submitLead called with data ->', {
            leadId: this.leadId,
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            company: this.company,
            budget: this.budget,
            siteLocation: this.siteLocation,
            projectDescription: this.projectDescription,
            typeOfProject: this.typeOfProject,
            projectScope: this.projectScope
        });

        updateLead({
            leadId: this.leadId,
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            company: this.company,
            budget: parseFloat(this.budget),
            siteLocation: this.siteLocation,
            projectDescription: this.projectDescription,
            typeOfProject: this.typeOfProject,
            projectScope: this.projectScope
        })
            .then(() => {
                console.log('Lead updated successfully');
                this.showForm = false;
                this.showSuccess = true;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Lead updated successfully!',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                console.error('Error updating Lead ->', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body ? error.body.message : 'Unknown error',
                        variant: 'error'
                    })
                );
            });
    }

    handleCloseSuccess() {
        console.log('handleCloseSuccess called');
        this.showSuccess = false;
        this.showForm = true;
    }

    goToPrevious() {
        console.log('Child: Dispatching previous event to parent');
        this.dispatchEvent(new CustomEvent('previous'));
    }
}