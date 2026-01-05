import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

// Apex Methods
import getAllStages from '@salesforce/apex/AreliaPathController.getAllStages';
import getPathStatus from '@salesforce/apex/AreliaPathController.getPathStatus';

const FIELDS = [
    'Opportunity.Client_Agreement_Sent__c',
    'Opportunity.Client_Agreement_Signed__c',
    'Opportunity.All_Vendors_Agreement_Completed__c',
    'Opportunity.StageName'
];

export default class AreliaPath extends LightningElement {
    // 1. Standard API property
    _recordId;
    @api 
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.effectiveRecordId = value;
            this.checkVisibility();
        }
    }

    @track effectiveRecordId;
    @track steps = [];
    @track isReady = false;
    @track hasAccess = true;
    @track isVisible = true; 

    // Internal storage for the "Race" data
    _allStages = [];
    _currentPathStatus; 
    
    wiredPathResult;

    // 3. Resolve ID (Kept your logic as is)
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
        } catch {
            // ignore
        }
    }

    checkVisibility() {
        if (this.effectiveRecordId && String(this.effectiveRecordId).startsWith('006')) {
            this.isVisible = true;
        } else {
            this.isVisible = false;
        }
    }

    // 4. Load Master List of Stages
    // FIX: Trigger buildSteps when this finishes
    @wire(getAllStages)
    wiredStages({ error, data }) {
        if (data) {
            this._allStages = data;
            this.tryBuildSteps(); // <--- TRY TO BUILD NOW
        } else if (error) {
            console.error('Error loading stage definitions:', error);
        }
    }

    // 5. Get Current Active Step
    // FIX: Trigger buildSteps when this finishes
    @wire(getPathStatus, { oppId: '$effectiveRecordId' })
    wiredPathStatus(result) {
        this.wiredPathResult = result;
        const { data, error } = result;

        if (!this.effectiveRecordId || !this.isVisible) return;

        if (data) {
            this.hasAccess = true;
            this.isReady = true;
            this._currentPathStatus = data; // <--- SAVE DATA
            this.tryBuildSteps(); // <--- TRY TO BUILD NOW
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

    // 6. Centralized Build Logic
    // Only runs if BOTH pieces of data are present
    tryBuildSteps() {
        // Guard clause: Do we have stages? Do we have a status?
        if (!this._allStages || this._allStages.length === 0 || !this._currentPathStatus) {
            return;
        }

        const currentActiveValue = this._currentPathStatus;
        const activeIndex = this._allStages.findIndex(s => s.value === currentActiveValue);
        const targetIndex = activeIndex === -1 ? 0 : activeIndex;

        this.steps = this._allStages.map((stage, index) => {
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