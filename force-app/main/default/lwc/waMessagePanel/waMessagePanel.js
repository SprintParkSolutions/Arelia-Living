import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';

import getUnifiedChat from '@salesforce/apex/WhatsAppController.getUnifiedChat';
import getUnifiedChatForOpportunity from '@salesforce/apex/WhatsAppController.getUnifiedChatForOpportunity';
import getUnifiedChatForProject from '@salesforce/apex/WhatsAppController.getUnifiedChatForProject'; // <-- NEW
import ensureChatForNumber from '@salesforce/apex/WhatsAppController.ensureChatForNumber';
import getFilesForChat from '@salesforce/apex/WhatsAppController.getFilesForChat';
import makePublicLink from '@salesforce/apex/WhatsAppController.makePublicLink';
import makePublicAndSendApex from '@salesforce/apex/WhatsAppController.makePublicAndSend';

import sendTextToNumber from '@salesforce/apex/WhatsAppService.sendText';
import sendTemplateToNumber from '@salesforce/apex/WhatsAppService.sendTemplate';
import sendMediaFromDocument from '@salesforce/apex/WhatsAppService.sendMediaFromDocument';

import LEAD_MOBILE from '@salesforce/schema/Lead.MobilePhone';
import LEAD_PHONE from '@salesforce/schema/Lead.Phone';


const POLL_MS = 5000;

export default class WaMessagePanel extends LightningElement {
  @api recordId;
  @api objectApiName; // <-- lets us detect Lead vs Opportunity

  @track toNumber = '';
  @track textBody = '';
  @track templateName = '';
  @track langCode = 'en_US';
  @track messages = [];
  @track sending = false;
  @track lastResult = '';
  @track refreshing = false;

  @track caption = '';
  chatId;
  lastUploadedDocId;
  @track files = [];

  @track selectedFile = { id: null, title: '', ext: '', sizeLabel: '', isPublic: false, publicUrl: '' };

  autoRefresh = true;
  lastUpdated = '';
  _timer = null;
  _lastSignature = '';


  // ===== getters (no inline expressions in HTML) =====
  get isSendTextDisabled() { return this.sending || !this.toNumber || !this.textBody; }
  get isSendTemplateDisabled() { return this.sending || !this.toNumber || !this.templateName || !this.langCode; }
  get makePublicVariant() { return this.selectedFile.isPublic ? 'neutral' : 'brand-outline'; }
  get makePublicLabel() { return this.selectedFile.isPublic ? 'Public Link Created' : 'Make Public'; }
  get isMakePublicDisabled() { return this.selectedFile.isPublic || this.sending; }
  get isPublicSendDisabled() { return !this.selectedFile.isPublic || this.sending || !this.toNumber; }



  // ===== get recordId from state on community too =====
  @wire(CurrentPageReference)
  parsePageRef(pr) {
    try {
      if (this.recordId) return;
      if (!pr) return;
      const st = pr.state || {};
      const rid = st.recordId || st.id;
      if (rid) { this.recordId = rid; return; }

      // also support /s/detail/{id} paths
      if (typeof window !== 'undefined') {
        const path = window.location.pathname || '';
        const m = path.match(/\/s\/detail\/([a-zA-Z0-9]{15,18})/);
        if (m && m[1]) this.recordId = m[1];
      }
    } catch (e) { }
  }

  // works in org when FLS/sharing allows — run ONLY on Lead pages
  @wire(getRecord, { recordId: '$recordId', fields: [LEAD_MOBILE, LEAD_PHONE] })
  wiredLead({ data }) {
    if ((this.objectApiName || '').toLowerCase() !== 'lead') return; // guard for Opportunity
    if (data && !this.toNumber) {
      const mobile = getFieldValue(data, LEAD_MOBILE);
      const phone = getFieldValue(data, LEAD_PHONE);
      const best = (mobile || phone || '').trim();
      this.toNumber = best ? this.normalizePhone(best) : this.toNumber;
      if (this.toNumber) this.ensureChat();
    }
  }

  // ===== lifecycle =====
  connectedCallback() {
    this.ensureRecordIdFromUrl();  // extra safety on community}
    this.refreshChat();
    this.startTimer();
  }
  disconnectedCallback() { this.stopTimer(); }

  ensureRecordIdFromUrl() {
    try {
      if (!this.recordId && typeof window !== 'undefined') {
        const u = new URL(window.location.href);
        const rid = u.searchParams.get('recordId') || u.searchParams.get('id');
        if (rid) this.recordId = rid;
      }
    } catch (e) { }
  }

  // ===== chat & files =====
  async ensureChat() {
    try {
      if (!this.toNumber) return;
      const id = await ensureChatForNumber({ e164OrDigits: this.toNumber });
      this.chatId = id;
      await this.loadFiles();
    } catch (e) { }
  }

  async loadFiles() {
    if (!this.chatId) return;
    try {
      this.files = await getFilesForChat({ chatId: this.chatId });
    } catch (e) {
      const msg = (e?.body?.message) || e?.message || String(e);
      this.lastResult = 'Files error: ' + msg;
    }
  }

  normalizePhone(raw) {
    const t = (raw || '').trim();
    if (!t) return '';
    if (t.startsWith('+')) return '+' + t.replace(/[^\d]/g, '');
    return t.replace(/[^\d+]/g, '');
  }

  // ===== refresh loop =====
  startTimer() { this.stopTimer(); if (this.autoRefresh) this._timer = setInterval(() => this.refreshChat(), POLL_MS); }
  stopTimer() { if (this._timer) { clearInterval(this._timer); this._timer = null; } }
  toggleAutoRefresh = (e) => { this.autoRefresh = !!e.target.checked; this.startTimer(); };
  manualRefresh = () => this.refreshChat(true);

  async refreshChat(force = false) {
    if (!this.recordId || this.refreshing) return;
    const listEl = this.template.querySelector('[data-chat]');
    const wasNearBottom = listEl ? (listEl.scrollHeight - listEl.scrollTop - listEl.clientHeight < 40) : true;

    this.refreshing = true;
    try {
      // Choose API by hosting object
      let raw = [];
      const obj = (this.objectApiName || '').toLowerCase();
      if (obj === 'opportunity') {
        raw = await getUnifiedChatForOpportunity({ opportunityId: this.recordId, limitCount: 300 });
      } else if (obj === 'project__c') {                          // <-- NEW
        raw = await getUnifiedChatForProject({ projectId: this.recordId, limitCount: 300 });
      } else {
        raw = await getUnifiedChat({ leadId: this.recordId, limitCount: 300 });
      }

      const onlyHumanMsgs = (raw || []).filter(r => {
        const t = (r.text || '').trim();
        return t && !t.startsWith('[STATUS]');
      });

      // infer phone if Lead fields weren't readable
      if (!this.toNumber && onlyHumanMsgs.length) {
        const guess = this.inferPhoneFromChat(onlyHumanMsgs);
        if (guess) {
          this.toNumber = this.normalizePhone(guess);
          await this.ensureChat();
        }
      }

      const sig = onlyHumanMsgs.length
        ? `${onlyHumanMsgs.length}:${onlyHumanMsgs[onlyHumanMsgs.length - 1].id || ''}:${onlyHumanMsgs[onlyHumanMsgs.length - 1].ts || ''}`
        : '0';

      if (force || sig !== this._lastSignature) {
        this._lastSignature = sig;

        this.messages = onlyHumanMsgs.map((r, i) => {
          const ts = r.ts ? new Date(r.ts) : null;
          const localTs = ts ? ts.toLocaleString() : '';
          const isOut = (r.dir || '').toUpperCase() === 'OUT';
          const rowClass = `row ${isOut ? 'row-out' : 'row-in'}`;
          const bubbleClass = `bubble ${isOut ? 'bubble-out' : 'bubble-in'}`;

          const media = (r.mediaType || '').toLowerCase();
          const isImage = media === 'image' || media.startsWith('image');

          const sfImageUrl = (isImage && r.contentDocumentId)
            ? `/sfc/servlet.shepherd/document/download/${r.contentDocumentId}?operation=VIEW`
            : null;
          const sfFileUrl = (!isImage && r.contentDocumentId)
            ? `/sfc/servlet.shepherd/document/download/${r.contentDocumentId}?operation=OPEN`
            : null;

          const imageUrl = sfImageUrl || (isImage ? r.externalUrl : null);
          const fileUrl = sfFileUrl || (!isImage ? r.externalUrl : null);

          return { ...r, key: `${i}-${(r.id || '')}`, localTs, rowClass, bubbleClass, imageUrl, fileUrl };
        });

        requestAnimationFrame(() => {
          const el = this.template.querySelector('[data-chat]');
          if (el && wasNearBottom) el.scrollTop = el.scrollHeight;
        });
      }
      this.lastUpdated = new Date().toLocaleTimeString();
    } catch (e) {
      const msg = (e?.body?.message) || e?.message || String(e);
      this.lastResult = msg;
    } finally {
      this.refreshing = false;
    }
  }

  // choose last OUT toNumber, else last IN fromNumber
  inferPhoneFromChat(list) {
    // try last OUT bound
    for (let i = list.length - 1; i >= 0; i--) {
      const m = list[i];
      if ((m.dir || '').toUpperCase() === 'OUT' && m.toNumber) return m.toNumber;
    }
    // else last IN sender
    for (let i = list.length - 1; i >= 0; i--) {
      const m = list[i];
      if ((m.dir || '').toUpperCase() === 'IN' && m.fromNumber) return m.fromNumber;
    }
    return null;
  }

  // ===== inputs =====
  onComposerKeyDown = (evt) => { if (evt.key === 'Enter' && !evt.shiftKey) { evt.preventDefault(); this.sendText(); } };
  onNumberChange(e) { this.toNumber = this.normalizePhone(e.target.value); this.ensureChat(); }
  onBodyChange(e) { this.textBody = e.target.value; }
  onTemplateName(e) { this.templateName = e.target.value; }
  onLang(e) { this.langCode = e.target.value; }
  onCaptionChange = (e) => { this.caption = e.target.value; }

  // ===== send actions =====
  async sendText() {
    this.sending = true;
    try {
      const res = await sendTextToNumber({ toE164: this.toNumber, body: this.textBody });
      this.lastResult = JSON.stringify(res, null, 2);
      this.textBody = '';
      requestAnimationFrame(() => {
        const input = this.template.querySelector('.text-textarea textarea');
        if (input) input.focus();
      });
      await this.refreshChat(true);
    } catch (e) {
      const msg = (e?.body?.message) || e?.message || String(e);
      this.lastResult = msg;
    } finally { this.sending = false; }
  }

  async sendTemplate() {
    this.sending = true;
    try {
      const res = await sendTemplateToNumber({
        toE164: this.toNumber, templateName: this.templateName, langCode: this.langCode, bodyParams: []
      });
      this.lastResult = JSON.stringify(res, null, 2);
      await this.refreshChat(true);
    } catch (e) {
      const msg = (e?.body?.message) || e?.message || String(e);
      this.lastResult = msg;
    } finally { this.sending = false; }
  }

  // upload → single card
  handleUploadFinished = async (evt) => {
    const files = evt.detail.files || [];
    if (files.length) {
      const f = files[0];
      const dot = (f.name || '').lastIndexOf('.');
      const ext = dot > -1 ? f.name.substring(dot + 1) : '';
      this.selectedFile = {
        id: f.documentId,
        title: dot > -1 ? f.name.substring(0, dot) : f.name,
        ext,
        sizeLabel: '',
        isPublic: false,
        publicUrl: ''
      };
      this.lastUploadedDocId = f.documentId;
      this.lastResult = `Uploaded: ${f.name}`;
      await this.loadFiles();
    }
  };

  // legacy (kept)
  async sendLastUploaded() {
    if (!this.lastUploadedDocId) return;
    this.sending = true;
    try {
      const res = await sendMediaFromDocument({
        contentDocumentId: this.lastUploadedDocId,
        toE164: this.toNumber,
        caption: this.caption || ''
      });
      this.lastResult = JSON.stringify(res, null, 2);
      this.caption = '';
      await this.refreshChat(true);
    } catch (e) {
      const msg = (e?.body?.message) || e?.message || String(e);
      this.lastResult = msg;
    } finally { this.sending = false; }
  }

  // step 1: make public
  async handleMakePublic() {
    if (!this.selectedFile.id) return;
    try {
      const url = await makePublicLink({ contentDocumentId: this.selectedFile.id });
      this.selectedFile = { ...this.selectedFile, isPublic: true, publicUrl: url };
      this.lastResult = `Public link created: ${url}`;
    } catch (err) {
      const msg = (err?.body?.message) || err?.message || String(err);
      this.lastResult = msg;
    }
  }

  // step 2: send via public link
  async handleSendPublic() {
    if (!this.selectedFile.id || !this.selectedFile.isPublic) return;
    this.sending = true;
    try {
      const res = await makePublicAndSendApex({
        contentDocumentId: this.selectedFile.id,
        toE164: this.toNumber,
        caption: this.caption || ''
      });
      this.lastResult = JSON.stringify(res, null, 2);
      this.caption = '';
      await this.refreshChat(true);
    } catch (err) {
      const msg = (err?.body?.message) || err?.message || String(err);
      this.lastResult = msg;
    } finally { this.sending = false; }
  }
}