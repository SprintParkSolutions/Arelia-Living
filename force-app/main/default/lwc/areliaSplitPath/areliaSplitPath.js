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
    // 1. Standard API property (Read-Only from Framework)
    _recordId;
    @api 
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        // If framework gives us an ID, set our internal tracker
        if (value) {
            this.effectiveRecordId = value;
            this.checkVisibility();
        }
    }

    // 2. Internal Tracker (Writable) - Wires will listen to THIS
    @track effectiveRecordId;

    @track steps = [];
    @track isReady = false;
    @track hasAccess = true;
    @track isVisible = true; 

    _allStages = [];
    wiredPathResult;

    // 3. Resolve ID for Experience Cloud (Robust URL Parsing)
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        // If framework already gave us an ID, don't overwrite it
        if (this._recordId) {
            this.effectiveRecordId = this._recordId;
            return;
        }

        const state = pageRef?.state || {};
        const fromState = state.recordId || state.id || state.c__recordId;

        if (fromState) {
            this.effectiveRecordId = fromState; // Write to internal var
            this.checkVisibility();
            return;
        }

        // Fallback: parse from URL
        try {
            const href = window.location.href;
            const url = new URL(href);
            const qp = url.searchParams.get('recordId') || url.searchParams.get('id');

            if (qp) {
                this.effectiveRecordId = qp; // Write to internal var
            } else {
                const anyId = href.match(/([a-zA-Z0-9]{15,18})/);
                if (anyId?.[1]) {
                    this.effectiveRecordId = anyId[1]; // Write to internal var
                }
            }
            this.checkVisibility();
        } catch {
            // ignore
        }
    }

    // Helper: Check if we are on an Opp (Simple ID Prefix Check)
    checkVisibility() {
        if (this.effectiveRecordId && String(this.effectiveRecordId).startsWith('006')) {
            this.isVisible = true;
        } else {
            this.isVisible = false;
        }
    }

    // 4. Load Master List of Stages
    @wire(getAllStages)
    wiredStages({ error, data }) {
        if (data) {
            this._allStages = data;
        } else if (error) {
            console.error('Error loading stage definitions:', error);
        }
    }

    // 5. Get Current Active Step (Using effectiveRecordId)
    @wire(getPathStatus, { oppId: '$effectiveRecordId' })
    wiredPathStatus(result) {
        this.wiredPathResult = result;
        const { data, error } = result;

        if (!this.effectiveRecordId || !this.isVisible) return;

        if (data) {
            this.hasAccess = true;
            this.isReady = true;
            this.buildSteps(data);
        } else if (error) {
            this.hasAccess = false;
            this.isReady = true;
            console.error('Error loading path status:', error);
        }
    }

    // 6. Watch for Record Changes (Using effectiveRecordId)
    @wire(getRecord, { recordId: '$effectiveRecordId', fields: FIELDS })
    wiredRecordWatcher({ data }) {
        if (data) {
            refreshApex(this.wiredPathResult);
        }
    }

    // Build Visual Steps
    buildSteps(currentActiveValue) {
        if (!this._allStages || this._allStages.length === 0) return;

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
            icon = 'utility:check';
        } else if (index === activeIndex) {
            stepClass += ' slds-is-current slds-is-active';
            icon = 'utility:check';
        } else {
            stepClass += ' slds-is-incomplete';
            icon = 'utility:check';
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