import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';

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
    isReady = false;
    hasAccess = true;

    // ✅ ensures it won’t show on other object pages
    isVisible = true;

    // ✅ Resolve recordId for Experience Cloud pages
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (this.recordId) return;

        const state = pageRef?.state || {};
        const fromState = state.recordId || state.id || state.c__recordId;

        if (fromState) {
            this.recordId = fromState;
            return;
        }

        // Fallback: parse from URL (Experience routes can vary)
        try {
            const href = window.location.href;

            // querystring support
            const url = new URL(href);
            const qp =
                url.searchParams.get('recordId') ||
                url.searchParams.get('id') ||
                url.searchParams.get('c__recordId');

            if (qp) {
                this.recordId = qp;
                return;
            }

            // /detail/<Id>
            const detailMatch = href.match(/\/detail\/([a-zA-Z0-9]{15,18})/);
            if (detailMatch?.[1]) {
                this.recordId = detailMatch[1];
                return;
            }

            // any 15/18 char Salesforce Id
            const anyId = href.match(/([a-zA-Z0-9]{15,18})/);
            if (anyId?.[1]) {
                this.recordId = anyId[1];
            }
        } catch (e) {
            // ignore
        }
    }

    // ✅ This will succeed only if recordId is a Lead and user has access
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ data, error }) {
        if (!this.recordId) return;

        if (data) {
            // Confirmed Lead page
            this.isVisible = true;
            this.hasAccess = true;
            this.isReady = true;

            this.buildStepsFromLead(data);
        } else if (error) {
            // If dropped on other object record pages => hide the component
            this.isVisible = false;
            this.hasAccess = false;
            this.isReady = true;

            // eslint-disable-next-line no-console
            console.warn('LeadProgressPath hidden (not Lead / no access):', JSON.stringify(error));
        }
    }

    buildStepsFromLead(data) {
        const approval = data.fields.Approval_Status__c?.value || 'Pending';
        const appointmentCompleted = data.fields.Appointment_Completed__c?.value || false;
        const converted = data.fields.IsConverted?.value || false;
        const hasSupervisor = !!data.fields.Supervisor_User__c?.value;

        const siteVisitStatus = data.fields.Site_Visit_Status__c?.value || 'Pending';
        const siteVisitApproved = siteVisitStatus === 'Approved';
        const siteVisitMgrApproved = !!data.fields.Site_Visit_Manager_Approval__c?.value;

        const stepsList = [];
        stepsList.push('Lead Created');                         // 0
        stepsList.push(`Approval - ${approval}`);               // 1

        if (approval === 'Approved') {
            stepsList.push(hasSupervisor ? 'Supervisor Assigned' : 'Assign Supervisor'); // 2
            stepsList.push('Appointment Scheduled');                                     // 3
            stepsList.push('Create Site Visit Report & Get Approval');                   // 4
            stepsList.push('Manager Approval of Site Visit Report');                     // 5
            stepsList.push('Lead Converted');                                            // 6
        }

        let currentStepIndex = 0;

        if (approval !== 'Approved') currentStepIndex = 1;
        else if (!hasSupervisor) currentStepIndex = 2;
        else if (!appointmentCompleted) currentStepIndex = 3;
        else if (!siteVisitApproved) currentStepIndex = 4;
        else if (!siteVisitMgrApproved) currentStepIndex = 5;
        else if (!converted) currentStepIndex = 6;
        else currentStepIndex = stepsList.length - 1;

        this.steps = stepsList.map((label, index) =>
            this.buildStep(label, index, currentStepIndex)
        );
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

        return {
            key: `${index}-${label}`,
            label,
            class: stepClass,
            icon
        };
    }
}