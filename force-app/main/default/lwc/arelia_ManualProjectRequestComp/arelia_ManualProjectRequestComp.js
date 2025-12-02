import { LightningElement, track } from 'lwc';
import createLead from '@salesforce/apex/Arelia_ManualProjectRequestController.createLead';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class Arelia_ManualProjectRequestComp extends LightningElement {
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

    @track countryCode = '+91'; // default India 🇮🇳
    phoneNumber = '';


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
        { label: '🇦🇪 +971 (UAE)', value: '+971' },
        { label: '🇸🇬 +65 (Singapore)', value: '+65' },
        { label: '🇦🇺 +61 (Australia)', value: '+61' },
        { label: '🇨🇦 +1 (Canada)', value: '+1' },
        { label: '🇩🇪 +49 (Germany)', value: '+49' },
        { label: '🇫🇷 +33 (France)', value: '+33' },
        { label: '🇯🇵 +81 (Japan)', value: '+81' }
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


    handleCountryChange(event) {
        this.countryCode = event.detail.value;
        this.updatePhone();
    }

    handlePhoneInput(event) {
        this.phoneNumber = event.target.value;
        this.updatePhone();

        if (!this.validatePhone(this.countryCode, this.phoneNumber)) {
            event.target.setCustomValidity('Invalid phone number for country');
        } else {
            event.target.setCustomValidity('');
        }
        event.target.reportValidity();
    }

    updatePhone() {
        this.phone = `${this.countryCode} ${this.phoneNumber}`.trim();
    }

    validateEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }

    // 🚫 Block alphabetic input while typing in phone field
    blockAlphabets(event) {
        const key = event.key;
        // Allow: digits, Backspace, Delete, Arrow keys, Tab
        const allowedKeys = ['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'Tab'];

        if (!/^[0-9]$/.test(key) && !allowedKeys.includes(key)) {
            event.preventDefault();
        }
    }

    validatePhone(countryCode, number) {
        const trimmed = number.replace(/\D/g, ''); // remove spaces, hyphens

        switch (countryCode) {
            case '+91': // India 🇮🇳
                return /^[6-9]\d{9}$/.test(trimmed); // starts 6-9 and total 10 digits
            case '+1': // USA & Canada 🇺🇸🇨🇦
                return /^[2-9]\d{9}$/.test(trimmed); // cannot start with 0 or 1
            case '+44': // UK 🇬🇧
                return /^7\d{9}$/.test(trimmed); // starts with 7, 10 digits
            case '+971': // UAE 🇦🇪
                return /^5\d{8}$/.test(trimmed); // 9 digits total
            case '+65': // Singapore 🇸🇬
                return /^[89]\d{7}$/.test(trimmed); // starts 8 or 9, 8 digits
            case '+61': // Australia 🇦🇺
                return /^4\d{8}$/.test(trimmed); // starts 4, 9 digits total
            case '+49': // Germany 🇩🇪
                return /^\d{10,13}$/.test(trimmed); // basic 10–13 digits
            case '+33': // France 🇫🇷
                return /^[67]\d{8}$/.test(trimmed); // starts 6 or 7, 9 digits total
            case '+81': // Japan 🇯🇵
                return /^\d{10}$/.test(trimmed); // 10 digits
            default:
                return trimmed.length >= 8; // fallback minimal rule
        }
    }

    handleChange(event) {
        const { name, value } = event.target;
        this[name] = value;

        if (name === 'email' && value) {
            if (!this.validateEmail(value)) {
                event.target.setCustomValidity('Please enter a valid email address');
            } else {
                event.target.setCustomValidity('');
            }
            event.target.reportValidity();
        }

        if (name === 'typeOfProject') {
            this.projectScopeOptions = this.scopeMap[value] || [];
            this.projectScope = '';
        }
    }

    get isScopeDisabled() {
        return this.projectScopeOptions.length === 0;
    }

    submitLead() {
         // 🚨 Email validation
        if (!this.validateEmail(this.email)) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invalid Email',
                    message: 'Please enter a valid email address.',
                    variant: 'error'
                })
            );
            return;
        }

        // 🚨 Phone validation
        const trimmedPhone = this.phoneNumber.trim();
        if (!this.validatePhone(this.countryCode, trimmedPhone)) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invalid Phone Number',
                    message: `Please enter a valid phone number for ${this.countryCode}.`,
                    variant: 'error'
                })
            );
            return;
        }
        
        createLead({
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            typeOfProject: this.typeOfProject,
            projectScope: this.projectScope,
            company: this.company,
            budget: parseFloat(this.budget),
            siteLocation: this.siteLocation,
            projectDescription: this.projectDescription
        })
            .then(result => {
                this.showForm = false;
                this.showSuccess = true;
                this.resetForm();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }

    resetForm() {
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.phone = '';
        this.company = '';
        this.budget = '';
        this.siteLocation = '';
        this.projectDescription = '';
        this.typeOfProject = '';
        this.projectScope = '';
        this.countryCode = '+91';
        this.phoneNumber = '';
    }

    handleCloseSuccess() {
        this.showSuccess = false;
        this.showForm = true;
    }
}