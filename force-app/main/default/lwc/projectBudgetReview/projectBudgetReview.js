import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

// Import Field References
import EST_BUDGET from '@salesforce/schema/Project__c.Supervisor_Estimated_Budget__c';
import COMPANY_SHARE from '@salesforce/schema/Project__c.Company_Profit_of_the_Project__c';
import REMAINING_PROJ_BUDGET from '@salesforce/schema/Project__c.Remaining_Project_Budget__c';
import REMAINING_BUDGET_PENDING from '@salesforce/schema/Project__c.Remaining_Budget_Pending__c';
import TOTAL_EXPENSES from '@salesforce/schema/Project__c.Total_Approved_Expenses__c';
import COMPLETION_STATUS from '@salesforce/schema/Project__c.Project_Completion_Status__c';
import SUPERVISOR_PROFIT_PCT from '@salesforce/schema/Project__c.Supervisor_Profit_Percentage__c';
import TOTAL_PROFIT from '@salesforce/schema/Project__c.Total_Profit__c';
import TOTAL_PROFIT_PCT from '@salesforce/schema/Project__c.Total_Profit_Percentage__c';

const FIELDS = [
    EST_BUDGET, COMPANY_SHARE, REMAINING_PROJ_BUDGET,
    REMAINING_BUDGET_PENDING, TOTAL_EXPENSES, COMPLETION_STATUS,
    SUPERVISOR_PROFIT_PCT, TOTAL_PROFIT, TOTAL_PROFIT_PCT
];

export default class ProjectBudgetReview extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    project;

    // Helper to extract values safely
    getVal(field) {
        return getFieldValue(this.project.data, field) || 0;
    }

    // --- Data Getters ---
    get estBudget() { return this.getVal(EST_BUDGET); }
    get companyShare() { return this.getVal(COMPANY_SHARE); }
    get remProjBudget() { return this.getVal(REMAINING_PROJ_BUDGET); }
    get remBudgetPending() { return this.getVal(REMAINING_BUDGET_PENDING); }
    get totalExpenses() { return this.getVal(TOTAL_EXPENSES); }
    
    // Divide by 100 because lightning-formatted-number handles the percentage visually
    get completionStatus() { return this.getVal(COMPLETION_STATUS) / 100; } 
    get supervisorProfitPct() { return this.getVal(SUPERVISOR_PROFIT_PCT) / 100; }
    get totalProfit() { return this.getVal(TOTAL_PROFIT); }
    get totalProfitPct() { return this.getVal(TOTAL_PROFIT_PCT) / 100; }

    // --- Calculation ---
    get finalRemainingBudget() {
        return this.remBudgetPending - this.totalExpenses;
    }

    // --- Dynamic Color Logic (Red, Yellow, Green) ---
    get resultCardClass() {
        const pending = this.remBudgetPending;
        const expenses = this.totalExpenses;

        let baseClass = 'slds-m-top_large slds-p-around_medium result-card ';

        // Safety check to prevent dividing by zero
        if (!pending || pending <= 0) {
            return baseClass + 'status-red'; 
        }

        const usedPercentage = (expenses / pending) * 100;

        // Return early to satisfy ESLint 'no-else-return'
        if (usedPercentage <= 50) {
            return baseClass + 'status-green';   // 0% - 50% used
        } 
        
        if (usedPercentage <= 80) {
            return baseClass + 'status-yellow';  // 51% - 80% used
        } 
        
        return baseClass + 'status-red';         // Over 80% used
    }
}