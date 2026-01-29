import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableTimeSlots from '@salesforce/apex/AppointmentController.getAvailableTimeSlots';
import updateAppointmentStatus from '@salesforce/apex/AppointmentController.updateAppointmentStatus';
import { getRecord } from 'lightning/uiRecordApi';
import APPOINTMENT_STATUS from '@salesforce/schema/Lead.Appointment_Status__c';

export default class AppointmentApproval extends LightningElement {
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
    currentStatus; // Lead.Appointment_Status__c

    connectedCallback() {
        // Get Lead Id from Experience Cloud page URL (?id=...)
        const params = new URLSearchParams(window.location.search);
        this.recordId = params.get('id');

        // Block past dates on the picker
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        this.minDate = `${yyyy}-${mm}-${dd}`;
    }

    // Pull current Appointment_Status__c so we can block reschedule if already Approved
    @wire(getRecord, { recordId: '$recordId', fields: [APPOINTMENT_STATUS] })
    wiredLead({ data, error }) {
        if (data) {
            this.currentStatus = data.fields.Appointment_Status__c.value;
        } else if (error) {
            // non-blocking; just log
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    handleApprove() {
        this.actionType = 'Approved';
        this.showConfirmPrompt = true;
        this.showReschedule = false;
    }

    showRescheduleForm() {
        this.actionType = 'Rescheduled';
        this.showConfirmPrompt = true;
    }

    confirmAction() {
        this.showConfirmPrompt = false;

        if (this.actionType === 'Approved') {
            this.submit('Approved');
            this.showReschedule = false;
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
                currentLeadId: this.recordId
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

        // ---- Date validation (no past date) ----
        const selected = new Date(this.selectedDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        selected.setHours(0, 0, 0, 0);

        if (selected < today) {
            this.showToast('Invalid Date', 'Please select today or a future date.', 'error');
            return;
        }

        // ---- Time validation for TODAY (no past time slot) ----
        // Works with: "9 AM", "9:30 AM", "9 AM - 10 AM", "9:30 AM - 10:30 AM"
        const isToday =
            new Date(this.selectedDate).toISOString().slice(0, 10) ===
            new Date().toISOString().slice(0, 10);

        if (isToday) {
            const now = new Date();

            // take start time before "-"
            const startTimeRaw = (this.selectedTimeSlot.split('-')[0] || '').trim();

            // match: hour (:minute)? AM/PM
            const timeParts = startTimeRaw.match(/(\d+)(?::(\d+))?\s*(AM|PM)/i);

            if (!timeParts) {
                this.showToast('Invalid Time Slot', 'Unable to parse selected time slot format.', 'error');
                return;
            }

            let hour = parseInt(timeParts[1], 10);
            const minute = parseInt(timeParts[2] || '0', 10);
            const ampm = (timeParts[3] || '').toUpperCase();

            if (ampm === 'PM' && hour !== 12) hour += 12;
            if (ampm === 'AM' && hour === 12) hour = 0;

            const slotDateTime = new Date();
            slotDateTime.setHours(hour, minute, 0, 0);

            if (slotDateTime <= now) {
                this.showToast('Invalid Time Slot', 'Selected time slot has already passed for today.', 'error');
                return;
            }
        }

        // ✅ proceed
        this.submit('Rescheduled', '', this.selectedDate, this.selectedTimeSlot);
    }


    submit(status, rejectionReason = '', rescheduleDate = null, timeSlot = '') {
        updateAppointmentStatus({
            leadId: this.recordId,
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