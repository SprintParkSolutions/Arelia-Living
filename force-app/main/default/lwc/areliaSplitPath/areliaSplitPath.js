import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

// Apex Methods
import getAllStages from '@salesforce/apex/AreliaPathController.getAllStages';
import getPathStatus from '@salesforce/apex/AreliaPathController.getPathStatus';

const FIELDS = [
    // --- NEW FIELDS ---
    'Opportunity.Architecture_Client_Approval_Sent__c',
    'Opportunity.Architecture_Manager_Approval__c',
    'Opportunity.Catalogue_Link_Sent__c',
    // --- EXISTING FIELDS ---
    'Opportunity.Client_Agreement_Sent__c',
    'Opportunity.Client_Agreement_Signed__c',
    'Opportunity.All_Vendors_Agreement_Completed__c',
    'Opportunity.StageName'
];
export default class AreliaPath extends LightningElement {
   @api 
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.effectiveRecordId = value;
            this.checkVisibility();
        }
    }
    _recordId;

    @track effectiveRecordId;
    @track steps = [];
    @track isReady = false;
    @track hasAccess = true;
    @track isVisible = true; 

    _allStages = [];
    _currentPathStatus; 
    wiredPathResult;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (this._recordId) {
            this.effectiveRecordId = this._recordId;
            return;
        }
        const state = pageRef?.state || {};
        const fromState = state.recordId || state.id || state.c__recordId;

        if (fromState) {
            this.effectiveRecordId = fromState;
            this.checkVisibility();
            return;
        }

        try {
            const href = window.location.href;
            const url = new URL(href);
            const qp = url.searchParams.get('recordId') || url.searchParams.get('id');

            if (qp) {
                this.effectiveRecordId = qp;
            } else {
                const anyId = href.match(/([a-zA-Z0-9]{15,18})/);
                if (anyId?.[1]) {
                    this.effectiveRecordId = anyId[1];
                }
            }
            this.checkVisibility();
        } catch (e) {
            // ESLint requires a comment or logic here
            console.warn('Could not parse Record ID from URL', e);
        }
    }

    checkVisibility() {
        if (this.effectiveRecordId && String(this.effectiveRecordId).startsWith('006')) {
            this.isVisible = true;
        } else {
            this.isVisible = false;
        }
    }

    @wire(getAllStages)
    wiredStages({ error, data }) {
        if (data) {
            this._allStages = data;
            this.tryBuildSteps();
        } else if (error) {
            console.error('Error loading stage definitions:', error);
        }
    }

    @wire(getPathStatus, { oppId: '$effectiveRecordId' })
    wiredPathStatus(result) {
        this.wiredPathResult = result;
        const { data, error } = result;

        if (!this.effectiveRecordId || !this.isVisible) return;

        if (data) {
            this.hasAccess = true;
            this.isReady = true;
            this._currentPathStatus = data;
            this.tryBuildSteps();
        } else if (error) {
            this.hasAccess = false;
            this.isReady = true;
            console.error('Error loading path status:', error);
        }
    }

    @wire(getRecord, { recordId: '$effectiveRecordId', fields: FIELDS })
    wiredRecordWatcher({ data }) {
        if (data) {
            refreshApex(this.wiredPathResult);
        }
    }

    tryBuildSteps() {
        if (!this._allStages || this._allStages.length === 0 || !this._currentPathStatus) {
            return;
        }

        const currentActiveValue = this._currentPathStatus;
        
        // --- VISIBILITY FILTER ---
        const specialStages = ['Negotiation/Review', 'Resumed'];
        let visibleStages;

        if (specialStages.includes(currentActiveValue)) {
            visibleStages = this._allStages;
        } else {
            // Filter out special stages if we are in normal flow
            visibleStages = this._allStages.filter(stage => !specialStages.includes(stage.value));
        }

        const activeIndex = visibleStages.findIndex(s => s.value === currentActiveValue);
        const targetIndex = activeIndex === -1 ? 0 : activeIndex;

        this.steps = visibleStages.map((stage, index) => {
            return this.buildStepObject(stage.label, index, targetIndex);
        });
    }

    buildStepObject(label, index, activeIndex) {
        let stepClass = 'slds-path__item';
        let icon = 'utility:check';

        if (index < activeIndex) {
            stepClass += ' slds-is-complete';
        } else if (index === activeIndex) {
            stepClass += ' slds-is-current slds-is-active';
        } else {
            stepClass += ' slds-is-incomplete';
        }

        return {
            key: `${index}-${label}`,
            label: label,
            class: stepClass,
            icon: icon
        };
    }

    handleRefresh() {
        refreshApex(this.wiredPathResult);
    }
}