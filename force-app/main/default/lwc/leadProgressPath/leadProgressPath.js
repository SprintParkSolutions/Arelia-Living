import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';

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
    mobileSteps = [];

    isReady = false;
    hasAccess = true;
    isVisible = true;

    get isMobile() {
        return FORM_FACTOR === 'Small'; // ✅ Salesforce Mobile
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (this.recordId) return;

        const state = pageRef?.state || {};
        const fromState = state.recordId || state.id || state.c__recordId;

        if (fromState) {
            this.recordId = fromState;
            return;
        }

        try {
            const href = window.location.href;
            const url = new URL(href);

            const qp =
                url.searchParams.get('recordId') ||
                url.searchParams.get('id') ||
                url.searchParams.get('c__recordId');

            if (qp) {
                this.recordId = qp;
                return;
            }

            const detailMatch = href.match(/\/detail\/([a-zA-Z0-9]{15,18})/);
            if (detailMatch?.[1]) {
                this.recordId = detailMatch[1];
                return;
            }

            const anyId = href.match(/([a-zA-Z0-9]{15,18})/);
            if (anyId?.[1]) {
                this.recordId = anyId[1];
            }
        } catch (e) {
            // ignore
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ data, error }) {
        if (!this.recordId) return;

        if (data) {
            this.isVisible = true;
            this.hasAccess = true;
            this.isReady = true;

            this.buildStepsFromLead(data);

            // ✅ Build mobile steps from the same steps
            this.mobileSteps = this.steps.map(s => {
                let mClass = 'mItem';
                if (s.class.includes('slds-is-complete')) mClass += ' isDone';
                else if (s.class.includes('slds-is-current')) mClass += ' isCurrent';
                else mClass += ' isNext';

                return { ...s, mClass };
            });

        } else if (error) {
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
        stepsList.push('Lead Created');
        stepsList.push(`Approval - ${approval}`);

        if (approval === 'Approved') {
            stepsList.push(hasSupervisor ? 'Supervisor Assigned' : 'Assign Supervisor');
            stepsList.push('Appointment Scheduled');
            stepsList.push('Create Site Visit Report & Get Approval');
            stepsList.push('Manager Approval of Site Visit Report');
            stepsList.push('Lead Converted');
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
