import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Lead.Appointment_Completed__c',
    'Lead.IsConverted',
    'Lead.Approval_Status__c',
    'Lead.Supervisor_User__c',
    'Lead.Site_Visit_Status__c',
    'Lead.Site_Visit_Manager_Approval__c'
];

export default class LeadProgressPath extends LightningElement {
    @api recordId;
    steps = [];

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ data, error }) {
        if (data) {
            const approval = data.fields.Approval_Status__c?.value || 'Pending';
            const appointmentCompleted = data.fields.Appointment_Completed__c?.value || false;
            const converted = data.fields.IsConverted?.value || false;
            const hasSupervisor = !!data.fields.Supervisor_User__c?.value;

            const siteVisitStatus = data.fields.Site_Visit_Status__c?.value || 'Pending';
            const siteVisitApproved = siteVisitStatus === 'Approved';
            const siteVisitMgrApproved = !!data.fields.Site_Visit_Manager_Approval__c?.value;

            // Build the linear flow
            const stepsList = [];
            stepsList.push('Lead Created');                         // 0
            stepsList.push(`Approval - ${approval}`);               // 1

            if (approval === 'Approved') {
                // 2: Supervisor assignment state
                stepsList.push(hasSupervisor ? 'Supervisor Assigned' : 'Assign Supervisor');

                // 3: Appointment stage
                stepsList.push('Appointment Scheduled');

                // 4: Site visit report approval
                stepsList.push('Create Site Visit Report & Get Approval');

                // 5: Manager approval of site visit report
                stepsList.push('Manager Approval of Site Visit Report');

                // 6: Conversion
                stepsList.push('Lead Converted');
            }

            // Decide current step pointer
            let currentStepIndex = 0;

            // if not approved yet, stay on Approval
            if (approval !== 'Approved') {
                currentStepIndex = 1;
            } else if (!hasSupervisor) {
                currentStepIndex = 2;
            } else if (!appointmentCompleted) {
                currentStepIndex = 3;
            } else if (!siteVisitApproved) {
                currentStepIndex = 4;
            } else if (!siteVisitMgrApproved) {
                currentStepIndex = 5;
            } else if (!converted) {
                currentStepIndex = 6;
            } else {
                // fully done (converted)
                currentStepIndex = stepsList.length - 1;
            }

            // Render steps
            this.steps = stepsList.map((label, index) => this.buildStep(label, index, currentStepIndex));
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading lead:', error);
        }
    }

    buildStep(label, index, currentStepIndex) {
        let stepClass = 'slds-path__item';
        let icon = 'utility:check';

        if (index < currentStepIndex) {
            stepClass += ' slds-is-complete';
            icon = 'utility:check';
        } else if (index === currentStepIndex) {
            stepClass += ' slds-is-current slds-is-active';
            icon = 'utility:clock';
        } else {
            stepClass += ' slds-is-incomplete';
            icon = 'utility:dash';
        }

        return { label, class: stepClass, icon };
    }
}