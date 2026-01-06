import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getProject from '@salesforce/apex/ProjectAdditionalBudgetController.getProject';
import approveRequest from '@salesforce/apex/ProjectAdditionalBudgetController.approveRequest';
import rejectRequest from '@salesforce/apex/ProjectAdditionalBudgetController.rejectRequest';

export default class ProjectAdditionalBudgetApproval extends LightningElement {
  projectId;
  project;
  error;
  isBusy = false;

  showHistory = false;

  get historyBtnLabel() {
    return this.showHistory ? 'Hide History' : 'View History';
  }

  @wire(CurrentPageReference)
  setCurrentPageRef(pageRef) {
    const st = pageRef?.state || {};
    this.projectId = st.id || st.c__id || st.recordId || st.c__recordId || this.projectId;

    if (!this.projectId) {
      this.project = null;
      this.error = 'Missing Project Id in URL. Use: /s/additional-budget-approval?id=PROJECT_ID';
      return;
    }
    this.loadProject();
  }

  toggleHistory() {
    this.showHistory = !this.showHistory;
  }

  loadProject() {
    this.isBusy = true;
    this.error = null;

    getProject({ projectId: this.projectId })
      .then((res) => {
        this.project = res;
      })
      .catch((e) => {
        this.project = null;
        this.error = this.normalizeError(e);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  approve() {
    this.runAction(approveRequest, 'Approved', 'Approved successfully. Notifications sent.');
  }

  reject() {
    this.runAction(rejectRequest, 'Rejected', 'Rejected successfully. Notification sent.');
  }

  runAction(apexFn, title, message) {
    this.isBusy = true;
    this.error = null;

    apexFn({ projectId: this.projectId })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'success' }));
        this.loadProject();
      })
      .catch((e) => {
        this.error = this.normalizeError(e);
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  normalizeError(e) {
    if (!e) return 'Unknown error';
    if (Array.isArray(e.body)) return e.body.map((x) => x.message).join(', ');
    if (e.body?.message) return e.body.message;
    return e.message || 'Unknown error';
  }
}
