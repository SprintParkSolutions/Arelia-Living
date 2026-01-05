import { LightningElement, api, track, wire } from "lwc";
import getPaymentTerms from "@salesforce/apex/PaymentTermController.getPaymentTerms";
import savePaymentTerms from "@salesforce/apex/PaymentTermController.savePaymentTerms";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";

export default class PaymentTermManagerAction extends LightningElement {
  @api recordId;

  /* ================= STATE ================= */

  @track terms = [];
  @track deletedTermIds = [];
  @track currentTotal = 0;

  @track isLoading = true;
  @track isEditMode = false;
  @track showResumeBtn = false;

  wiredTermsResult;

  /* ================= LOAD DATA ================= */

  @wire(getPaymentTerms, { recordId: "$recordId" })
  wiredTerms(result) {
    this.wiredTermsResult = result;
    const { data, error } = result;

    if (data) {
      this.isLoading = false;

      // 🔹 CASE 1: No existing terms → start with ONE editable row
      if (data.length === 0) {
        this.isEditMode = true;
        this.showResumeBtn = false;

        this.terms = [
          {
            TempId: Date.now(),
            serialNumber: 1,
            Term_Label__c: "",
            Percentage__c: 0,
            Due_Date__c: null,
            Payment_Received__c: false
          }
        ];

        this.calculateTotal();
        return;
      }

      // 🔹 CASE 2: Terms exist → show resume screen
      this.showResumeBtn = true;
      this.isEditMode = false;

      this.terms = data.map((item, index) => ({
        ...item,
        TempId: item.Id,
        serialNumber: index + 1,
        Term_Label__c: item.Term_Label__c || item.Name || ""
      }));

      this.calculateTotal();
    } else if (error) {
      this.isLoading = false;
      this.showToast(
        "Error",
        error.body?.message || error.message,
        "error"
      );
    }
  }

  /* ================= GETTERS ================= */

  get minDueDate() {
    return new Date().toISOString().split("T")[0];
  }

  get isInvalid() {
    return Math.abs(this.currentTotal - 100) > 0.01;
  }

  get totalStatusClass() {
    return this.isInvalid
      ? "slds-text-color_error"
      : "slds-text-color_success";
  }

  /* ================= VIEW FLOW ================= */

  handleResume() {
    this.showResumeBtn = false; // show view mode
  }

  handleEditMode() {
    this.isEditMode = true;
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  /* ================= ROW HANDLERS ================= */

  handleAddRow() {
    this.terms = [
      ...this.terms,
      {
        TempId: Date.now(),
        serialNumber: this.terms.length + 1,
        Term_Label__c: "",
        Percentage__c: 0,
        Due_Date__c: null,
        Payment_Received__c: false
      }
    ];
    this.calculateTotal();
  }

  handleDeleteRow(event) {
    const index = event.currentTarget.dataset.index;

    // Prevent deleting the last row
    if (this.terms.length === 1) {
      this.showToast(
        "Warning",
        "At least one payment term is required.",
        "warning"
      );
      return;
    }

    if (this.terms[index].Id) {
      this.deletedTermIds.push(this.terms[index].Id);
    }

    this.terms.splice(index, 1);

    // Reindex serial numbers
    this.terms = this.terms.map((t, i) => ({
      ...t,
      serialNumber: i + 1
    }));

    this.calculateTotal();
  }

  handleChange(event) {
    const index = event.currentTarget.dataset.index;
    const field = event.currentTarget.dataset.field;

    this.terms[index][field] =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.target.value;

    if (field === "Percentage__c") {
      this.calculateTotal();
    }
  }

  calculateTotal() {
    this.currentTotal = this.terms.reduce(
      (sum, t) => sum + (parseFloat(t.Percentage__c) || 0),
      0
    );
  }

  /* ================= SAVE ================= */

  handleSave() {
    if (this.isInvalid) {
      this.showToast(
        "Error",
        "Total percentage must equal 100%.",
        "error"
      );
      return;
    }

    const payload = this.terms.map(t => {
      const row = { ...t };
      delete row.TempId;
      delete row.serialNumber;
      return row;
    });

    savePaymentTerms({
      terms: payload,
      recordId: this.recordId,
      termsToDelete: this.deletedTermIds
    })
      .then(() => {
        this.showToast("Success", "Payment terms saved", "success");
        this.dispatchEvent(new CloseActionScreenEvent());
      })
      .catch(error => {
        this.showToast(
          "Error",
          error.body?.message || "Error saving payment terms",
          "error"
        );
      });
  }

  /* ================= UTIL ================= */

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({ title, message, variant })
    );
  }
}
