import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableTimeSlots from '@salesforce/apex/AppointmentControllerToOpp.getAvailableTimeSlots';
import updateAppointmentStatus from '@salesforce/apex/AppointmentControllerToOpp.updateAppointmentStatus';
import { getRecord } from 'lightning/uiRecordApi';
import OPP_APPT_STATUS from '@salesforce/schema/Opportunity.Re_Visit_Site_Appointment_Status__c';

export default class AppointmentApprovalToOpp extends LightningElement {
    @track showReschedule = false;
    @track showConfirmation = false;
    @track showConfirmPrompt = false;
    @track timeSlotOptions = [];
    @track selectedTimeSlot = '';
    @track selectedDate = '';
    @track confirmationMessage = '';
    @track actionType = '';
    @track buttonsDisabled = false;

    recordId;
    minDate;
    currentStatus; // Opportunity.Re_Visit_Site_Appointment_Status__c

    connectedCallback() {
        // Get Opportunity Id from Experience Cloud page URL (?id=...)
        const params = new URLSearchParams(window.location.search);
        this.recordId = params.get('id');

        // Block past dates on the picker
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        this.minDate = `${yyyy}-${mm}-${dd}`;
    }

    // Pull current Re_Visit_Site_Appointment_Status__c so we can block reschedule if already Approved
    @wire(getRecord, { recordId: '$recordId', fields: [OPP_APPT_STATUS] })
    wiredOpp({ data, error }) {
        if (data) {
            this.currentStatus = data.fields.Re_Visit_Site_Appointment_Status__c.value;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    handleApprove() {
        this.actionType = 'Approved';
        this.showConfirmPrompt = true;
    }

    showRescheduleForm() {
        this.actionType = 'Rescheduled';
        this.showConfirmPrompt = true;
    }

    confirmAction() {
        this.showConfirmPrompt = false;

        if (this.actionType === 'Approved') {
            this.submit('Approved');
            return;
        }

        if (this.actionType === 'Rescheduled') {
            // Guardrail: if already Approved, block reschedule in UI (Apex also enforces)
            if (this.currentStatus === 'Approved') {
                this.showToast('Error', 'This appointment is already approved and cannot be rescheduled.', 'error');
                return;
            }
            this.showReschedule = true;
        }
    }

    cancelAction() {
        this.actionType = '';
        this.showConfirmPrompt = false;
    }

    async handleDateChange(event) {
        this.selectedDate = event.target.value;
        this.selectedTimeSlot = '';
        this.timeSlotOptions = [];

        if (!this.selectedDate || !this.recordId) return;

        try {
            const slots = await getAvailableTimeSlots({
                forDate: this.selectedDate,
                currentOpportunityId: this.recordId
            });
            this.timeSlotOptions = (slots || []).map(s => ({ label: s, value: s }));
            if (this.timeSlotOptions.length === 0) {
                this.showToast('No Slots', 'No time slots available for the selected date.', 'warning');
            }
        } catch (e) {
            const msg = e?.body?.message || 'Failed to load time slots.';
            this.showToast('Error', msg, 'error');
        }
    }

    handleTimeSlotChange(event) {
        this.selectedTimeSlot = event.detail.value;
    }

    submitReschedule() {
        if (!this.selectedDate || !this.selectedTimeSlot) {
            this.showToast('Missing Input', 'Please select both date and time slot.', 'error');
            return;
        }

        // Prevent past dates
        const selected = new Date(this.selectedDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (selected < today) {
            this.showToast('Invalid Date', 'Please select a future date.', 'error');
            return;
        }

        this.submit('Rescheduled', '', this.selectedDate, this.selectedTimeSlot);
    }

    submit(status, rejectionReason = '', rescheduleDate = null, timeSlot = '') {
        updateAppointmentStatus({
            opportunityId: this.recordId,
            status,
            rejectionReason,
            rescheduleDate,
            timeSlot
        })
            .then(() => {
                this.confirmationMessage = `✅ Appointment ${status} successfully!`;
                this.showConfirmation = true;
                this.showReschedule = false;
                this.buttonsDisabled = true;
                this.currentStatus = status;
            })
            .catch((error) => {
                const msg = error?.body?.message || 'Something went wrong.';
                this.showToast('Error', msg, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}