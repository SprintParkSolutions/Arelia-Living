import { LightningElement, api, track, wire } from "lwc";
import { refreshApex } from "@salesforce/apex"; 
import getPaymentTerms from "@salesforce/apex/PaymentTermController.getPaymentTerms";
import savePaymentTerms from "@salesforce/apex/PaymentTermController.savePaymentTerms";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";

export default class PaymentTermManagerAction extends LightningElement {
  @api recordId;
  
  @track terms = [];
  @track deletedTermIds = [];
  @track currentTotal = 0;
  
  @track isLoading = true;
  @track isEditMode = false;      
  @track showResumeBtn = false;   

  wiredTermsResult;

  @wire(getPaymentTerms, { recordId: '$recordId' })
  wiredTerms(result) {
    this.wiredTermsResult = result;
    const { data, error } = result;

    if (data) {
      this.isLoading = false;
      
      if (data.length === 0) {
        this.terms = []; 
        this.handleAddRow(); 
        this.isEditMode = true; 
        this.showResumeBtn = false;
      } else {
        this.showResumeBtn = true;
        this.isEditMode = false;

        this.terms = data.map((item, index) => {
          let displayLabel = item.Term_Label__c;
          if (!displayLabel && item.Name && item.Name !== item.Id) {
            displayLabel = item.Name;
          }
          return {
            ...item,
            TempId: item.Id,
            Term_Label__c: displayLabel || "",
            serialNumber: index + 1 // Initial Serial Number
          };
        });
        this.calculateTotal();
      }
    } else if (error) {
      this.isLoading = false;
      console.error("Error fetching terms:", error);
      this.showToast("Error Loading Data", error.body ? error.body.message : error.message, "error");
    }
  }

  get minDueDate() {
    const today = new Date();
    const y = today.getFullYear();
    const m = String(today.getMonth() + 1).padStart(2, "0");
    const d = String(today.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  get isInvalid() {
    return Math.abs(this.currentTotal - 100) > 0.01;
  }

  get totalStatusClass() {
    return this.isInvalid ? "slds-text-color_error" : "slds-text-color_success";
  }

  // --- Logic Handlers ---

  handleResume() {
    this.showResumeBtn = false; 
  }

  handleEditMode() {
    this.isEditMode = true;
  }

  handleCancel() {
    this.isLoading = true; 
    this.deletedTermIds = [];
    this.showResumeBtn = true; 
    
    refreshApex(this.wiredTermsResult)
      .finally(() => {
          this.isLoading = false; 
      });
  }

  // --- NEW FUNCTION to recalculate 1, 2, 3... ---
  reindexTerms() {
    this.terms = this.terms.map((term, index) => {
        return { ...term, serialNumber: index + 1 };
    });
  }

  handleAddRow() {
    this.terms.push({
      TempId: Date.now(),
      Term_Label__c: "",
      Percentage__c: 0,
      Due_Date__c: null,
      Payment_Received__c: false
    });
    // Calculate serial numbers after adding
    this.reindexTerms();
    this.calculateTotal();
  }

  handleDeleteRow(event) {
    const index = event.currentTarget.dataset.index;
    if (this.terms[index].Id) {
      this.deletedTermIds.push(this.terms[index].Id);
    }
    this.terms.splice(index, 1);
    // Calculate serial numbers after deleting (e.g., 1, 3 becomes 1, 2)
    this.reindexTerms(); 
    this.calculateTotal();
  }

  handleChange(event) {
    const index = event.currentTarget.dataset.index;
    const field = event.currentTarget.dataset.field;
    if (event.target.type === "checkbox") {
      this.terms[index][field] = event.target.checked;
    } else {
      this.terms[index][field] = event.target.value;
    }
    if (field === "Percentage__c") {
      this.calculateTotal();
    }
  }

  calculateTotal() {
    this.currentTotal = this.terms.reduce((sum, item) => {
      return sum + (parseFloat(item.Percentage__c) || 0);
    }, 0);
  }

  handleSave() {
    const invalidDueDates = this.terms.some(
      (t) => t.Due_Date__c && new Date(t.Due_Date__c) < new Date(this.minDueDate)
    );
    if (invalidDueDates) {
      this.showToast("Invalid Date", "Due dates cannot be in the past.", "error");
      return;
    }

    const allValid = this.terms.every(
      (term) => term.Term_Label__c && term.Term_Label__c.trim() !== ""
    );
    if (!allValid) {
      this.showToast("Error", "Please provide a Name for all terms.", "error");
      return;
    }

    this.isLoading = true; 

    // Remove UI-only properties before sending to Apex
    const termsToSave = this.terms.map((row) => {
      let cleanRow = { ...row };
      delete cleanRow.TempId; 
      delete cleanRow.serialNumber; // IMPORTANT: Remove S.No so Apex doesn't fail
      return cleanRow;
    });

    savePaymentTerms({
      terms: termsToSave,
      recordId: this.recordId,
      termsToDelete: this.deletedTermIds
    })
      .then(() => {
        this.showToast("Success", "Payment terms saved.", "success");
        this.deletedTermIds = [];
        this.closeQuickAction();
        return refreshApex(this.wiredTermsResult);
      })
      .catch((error) => {
        this.isLoading = false; 
        this.showToast("Error", error.body?.message || "Unknown error", "error");
      });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
  
  closeQuickAction() {
      this.dispatchEvent(new CloseActionScreenEvent());
  }
}