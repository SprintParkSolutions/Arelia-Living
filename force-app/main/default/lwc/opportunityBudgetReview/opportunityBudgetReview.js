import { LightningElement, api, track, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import { updateRecord, getRecordNotifyChange } from "lightning/uiRecordApi";

// ✅ IMPORTANT: confirm these 3 API names exist in your org (change if needed)
import OPP_ID from "@salesforce/schema/Opportunity.Id";
import CUSTOMER_BUDGET from "@salesforce/schema/Opportunity.Estimated_Budget__c";
import SUPERVISOR_BUDGET from "@salesforce/schema/Opportunity.Supervisor_Estimated_Budget__c";
import DURATION from "@salesforce/schema/Opportunity.Project_Estimated_Completion_Months__c";

import getBudgetReview from "@salesforce/apex/OpportunityBudgetReviewController.getBudgetReview";
import saveChildRows from "@salesforce/apex/OpportunityBudgetReviewController.saveChildRows";

export default class OpportunityBudgetReview extends LightningElement {
    @api recordId;

    loading = true;
    isReadOnly = true;
    errorText = "";

    customerBudget = null;
    supervisorBudget = null;
    finalBudget = null;

    customerBudgetText = "";
    supervisorBudgetText = "";
    duration = "";

    customerBudgetSource = "";
    supervisorBudgetSource = "";

    @track architectureRows = [];
    @track paymentTermRows = [];

    architectureDraftValues = [];
    paymentTermDraftValues = [];

    wiredResult;

    // ✅ Community recordId support
    @wire(CurrentPageReference)
    pageRefHandler(pageRef) {
        if (!this.recordId && pageRef?.state) {
            this.recordId = pageRef.state.recordId || pageRef.state.c__recordId || this.recordId;
        }
    }

    @wire(getBudgetReview, { opportunityId: "$recordId" })
    wiredBudget(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.loading = false;

        if (error) {
            this.errorText = this.err(error);
            return;
        }
        if (data) {
            this.applyDto(data);
        }
    }

    get editButtonLabel() {
        return this.isReadOnly ? "Edit" : "Cancel";
    }

    get isSaveDisabled() {
        return this.loading || this.isReadOnly || !!this.errorText;
    }

    get durationLabel() {
        return this.duration ? this.duration : "—";
    }

    get architectureTotal() {
        return (this.architectureRows || []).reduce((sum, r) => sum + (Number(r.amount) || 0), 0);
    }

    get architectureColumns() {
        return [
            { label: "Architecture Design", fieldName: "name", type: "text" },
            { label: "Client Approval", fieldName: "clientApproval", type: "boolean" },
            { label: "Manager Approval", fieldName: "managerApproval", type: "boolean" },
            { label: "Architecture Budget (₹)", fieldName: "amount", type: "number", editable: !this.isReadOnly }
        ];
    }

    get paymentTermColumns() {
        return [
            { label: "Term Label", fieldName: "termLabel", type: "text", editable: !this.isReadOnly },
            { label: "Percentage", fieldName: "displayPercent", type: "percent", editable: !this.isReadOnly },
            { label: "Due Date", fieldName: "dueDate", type: "date", editable: !this.isReadOnly },
            { label: "Payment Received", fieldName: "paymentReceived", type: "boolean", editable: !this.isReadOnly }
        ];
    }

    toggleEdit() {
        this.isReadOnly = !this.isReadOnly;
        if (this.isReadOnly) refreshApex(this.wiredResult);
    }

    onCustomerInput(e) {
        this.customerBudgetText = e.target.value;
        this.customerBudget = this.toNumber(this.customerBudgetText);
    }

    onSupervisorInput(e) {
        this.supervisorBudgetText = e.target.value;
        this.supervisorBudget = this.toNumber(this.supervisorBudgetText);
        this.finalBudget = this.supervisorBudget;
    }

    onDurationInput(e) {
        this.duration = e.target.value;
    }

    onArchChange(e) {
        this.architectureDraftValues = e.detail.draftValues;
    }

    onTermChange(e) {
        this.paymentTermDraftValues = e.detail.draftValues;
    }

    async save() {
        this.loading = true;
        try {
            // ✅ ALWAYS read latest DOM values
            const custInp = this.template.querySelector('lightning-input[data-id="customerBudget"]');
            const supInp = this.template.querySelector('lightning-input[data-id="supervisorBudget"]');
            const durInp = this.template.querySelector('lightning-input[data-id="duration"]');

            const latestCust = this.toNumber(custInp?.value);
            const latestSup = this.toNumber(supInp?.value);
            const latestDur = (durInp?.value || "").trim();

            // ✅ 1) UPDATE OPPORTUNITY USING UI API (MOST RELIABLE)
            const fields = {};
            fields[OPP_ID.fieldApiName] = this.recordId;

            if (latestCust !== null) fields[CUSTOMER_BUDGET.fieldApiName] = latestCust;
            if (latestSup !== null) fields[SUPERVISOR_BUDGET.fieldApiName] = latestSup;
            if (latestDur) fields[DURATION.fieldApiName] = latestDur;

            if (Object.keys(fields).length > 1) {
                await updateRecord({ fields });
                await getRecordNotifyChange([{ recordId: this.recordId }]);
            }

            // ✅ 2) SAVE CHILDREN THROUGH APEX
            const mergedArch = this.mergeDrafts(this.architectureRows, this.architectureDraftValues);
            const mergedTerms = this.mergeDrafts(this.paymentTermRows, this.paymentTermDraftValues);

            const termsPayload = mergedTerms.map((p) => {
                const display = p.displayPercent; // 0.5
                const stored = (display === null || display === undefined || display === "")
                    ? null
                    : this.toNumber(display) * 100; // 50
                return {
                    id: p.id,
                    termLabel: p.termLabel,
                    percentage: stored,
                    dueDate: p.dueDate,
                    paymentReceived: p.paymentReceived
                };
            });

            const dto = await saveChildRows({
                opportunityId: this.recordId,
                req: {
                    architectureRows: mergedArch.map((r) => ({ id: r.id, amount: this.toNumber(r.amount) })),
                    paymentTerms: termsPayload
                }
            });

            this.applyDto(dto);
            await refreshApex(this.wiredResult);

            this.toast("Success", "Budget Review updated successfully.", "success");
            this.isReadOnly = true;
            this.architectureDraftValues = [];
            this.paymentTermDraftValues = [];

        } catch (e) {
            this.toast("Error", this.err(e), "error");
        } finally {
            this.loading = false;
        }
    }

    applyDto(dto) {
        this.errorText = "";

        this.customerBudget = dto?.customerBudget ?? null;
        this.supervisorBudget = dto?.supervisorBudget ?? null;
        this.finalBudget = dto?.finalBudget ?? null;

        this.customerBudgetText = this.customerBudget !== null ? String(this.customerBudget) : "";
        this.supervisorBudgetText = this.supervisorBudget !== null ? String(this.supervisorBudget) : "";
        this.duration = dto?.estimatedDuration ?? "";

        this.customerBudgetSource = dto?.customerBudgetSource ?? "";
        this.supervisorBudgetSource = dto?.supervisorBudgetSource ?? "";

        this.architectureRows = (dto?.architectureRows || []).map((r) => ({
            id: r.id,
            name: r.name,
            amount: r.amount,
            clientApproval: r.clientApproval,
            managerApproval: r.managerApproval
        }));

        this.paymentTermRows = (dto?.paymentTerms || []).map((p) => {
            const stored = p.percentage;
            return {
                id: p.id,
                termLabel: p.termLabel,
                percentage: stored,
                displayPercent: stored === null ? null : Number(stored) / 100,
                dueDate: p.dueDate,
                paymentReceived: p.paymentReceived
            };
        });
    }

    toNumber(value) {
        if (value === null || value === undefined) return null;
        const s = String(value).replace(/,/g, "").replace(/[^\d.-]/g, "").trim();
        if (!s) return null;
        const n = Number(s);
        return Number.isNaN(n) ? null : n;
    }

    mergeDrafts(baseRows, drafts) {
        const map = new Map((baseRows || []).map((r) => [r.id, { ...r }]));
        (drafts || []).forEach((d) => {
            const existing = map.get(d.id);
            if (existing) map.set(d.id, { ...existing, ...d });
        });
        return Array.from(map.values());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    err(error) {
        if (Array.isArray(error?.body)) return error.body.map((x) => x.message).join(", ");
        return error?.body?.message || error?.message || "Unknown error";
    }
}
