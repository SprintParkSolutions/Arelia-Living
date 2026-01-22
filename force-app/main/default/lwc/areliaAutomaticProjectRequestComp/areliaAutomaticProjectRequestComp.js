import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import getMasterData from '@salesforce/apex/InteriorMasterService.getMasterData';
import saveRequest from '@salesforce/apex/InteriorAutoProjectRequestService.saveRequest';
import fetchLeadForAutoRequest
    from '@salesforce/apex/InteriorAutoProjectRequestService.fetchLeadForAutoRequest';
import fetchExistingRequest
    from '@salesforce/apex/InteriorAutoProjectRequestService.fetchExistingRequest';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import SITE_URL from '@salesforce/label/c.Arelia_Site_Label';

export default class AreliaAutomaticProjectRequestComp extends LightningElement {
    @api leadId;
    @api quotationType;

    @track currentStep = 1;

    // master data
    allProjectTypes = [];
    allCategories = [];
    allRooms = [];
    allDesigns = [];
    allPlanLevels = [];

    // step1 fields
    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    company = '';
    address = '';
    siteSpace = '';
    description = '';

    // selections
    selectedProjectTypeId;
    selectedCategoryId;

    /**
     * Room qty per room record (Interior_Room__c)
     * { roomId: qty }
     */
    @track roomQuantities = {};

    selectedPlanLevel;

    /**
     * ✅ NEW: Instead of roomId, we track current room INSTANCE.
     * Example instanceKey: `${roomId}__1`
     */
    currentRoomInstanceKey;

    /**
     * ✅ NEW: Design per room INSTANCE (supports qty > 1)
     * { instanceKey: { roomId, instanceIndex, designId, designName, price, quantity, lineAmount, imageUrl } }
     */
    @track roomDesignMap = {};

    totalBudget = 0;

    // flags
    @track isImageModalOpen = false;
    modalImageUrl;
    modalTitle;

    isSaving = false;

    // initial loading
    @track isInitLoading = true;
    hasInitLoaded = false;

    hasExistingRequest = false;

    labels = {
        siteUrl: SITE_URL
    };

    // ===============================
    // CONFIG (dynamic-friendly)
    // ===============================
    AUTO_DEFAULT_ROOMS = true;      // auto fill qty=1 for all rooms in selected category
    MIN_ROOMS_FOR_BHK = true;       // optional validation (kept generic)

    // -----------------------------
    // URL HELPERS
    // -----------------------------
    get siteBaseUrl() {
        try {
            const raw = this.labels.siteUrl;
            const sourceUrl = raw ? new URL(raw) : new URL(window.location.href);

            const origin = sourceUrl.origin;
            const segments = (sourceUrl.pathname || '').split('/').filter((seg) => !!seg);
            const communitySegment = segments.length ? `/${segments[0]}` : '';
            return `${origin}${communitySegment}`;
        } catch (e) {
            const loc = window.location;
            const segs = (loc.pathname || '').split('/').filter((seg) => !!seg);
            const communitySegment = segs.length ? `/${segs[0]}` : '';
            return `${loc.origin}${communitySegment}`;
        }
    }

    resolveImageUrl(rel) {
        if (!rel) return null;
        if (rel.startsWith('http://') || rel.startsWith('https://')) return rel;
        const base = this.siteBaseUrl;
        const normalized = rel.startsWith('/') ? rel : `/${rel}`;
        return `${base}${normalized}`;
    }

    // -----------------------------
    // LEAD ID
    // -----------------------------
    connectedCallback() {
        this.ensureInitialLoad();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (!pageRef) return;

        const idFromUrl =
            (pageRef.state && pageRef.state.id) ||
            (pageRef.state && pageRef.state.c__id);

        if (idFromUrl && idFromUrl !== this.leadId) {
            // eslint-disable-next-line @lwc/lwc/no-api-reassignments
            this.leadId = idFromUrl;
        }

        this.ensureInitialLoad();
    }

    renderedCallback() {
        this.ensureInitialLoad();
    }

    ensureInitialLoad() {
        if (this.hasInitLoaded) return;
        if (!this.leadId) return;
        this.loadInitialData();
    }

    // -----------------------------
    // Initial data load
    // -----------------------------
    loadInitialData() {
        if (this.hasInitLoaded || !this.leadId) return;

        this.isInitLoading = true;
        this.hasInitLoaded = true;

        const masterPromise = getMasterData();
        const leadPromise = fetchLeadForAutoRequest({ leadId: this.leadId });
        const existingPromise = fetchExistingRequest({ leadId: this.leadId });

        Promise.all([masterPromise, leadPromise, existingPromise])
            .then(([res, leadRec, existing]) => {
                this.allProjectTypes = res.projectTypes || [];
                this.allCategories = res.categories || [];
                this.allRooms = res.rooms || [];
                this.allDesigns = res.designs || [];
                this.allPlanLevels = res.designLevels || [];

                if (leadRec) {
                    this.applyLeadDefaults(leadRec);
                }

                if (existing) {
                    this.applyExistingRequest(existing);
                }

                // If category already exists (prefill) and no room qty yet -> default
                if (this.selectedCategoryId && this.AUTO_DEFAULT_ROOMS && Object.keys(this.roomQuantities).length === 0) {
                    this.applyDefaultRoomsForCategory(this.selectedCategoryId);
                }
            })
            .catch((err) => {
                this.showToast(
                    'Error',
                    err && err.body && err.body.message ? err.body.message : 'Unable to load project data.',
                    'error'
                );
            })
            .finally(() => {
                this.isInitLoading = false;
            });
    }

    applyLeadDefaults(leadRec) {
        this.firstName = leadRec.FirstName || '';
        this.lastName = leadRec.LastName || '';
        this.email = leadRec.Email || '';
        this.phone = leadRec.Phone || '';
        this.company = leadRec.Company || '';
        this.address = leadRec.Site_Location__c || '';
        this.siteSpace = leadRec.Site_Space__c || '';
        this.description = leadRec.Project_Description__c || '';

        this.totalBudget = leadRec.Estimated_Budget__c || 0;

        this.selectedProjectTypeId = leadRec.Interior_Project_Type__c || null;
        this.selectedCategoryId = leadRec.Interior_Category__c || null;
        this.selectedPlanLevel = leadRec.Plan_Level__c || null;

        if (!this.quotationType && leadRec.Project_Request_Quotation_Type__c) {
            // eslint-disable-next-line @lwc/lwc/no-api-reassignments
            this.quotationType = leadRec.Project_Request_Quotation_Type__c;
        }
    }

    /**
     * Existing request support:
     * - Rooms: qtyMap
     * - RoomDesigns: may be stored as multiple lines already OR single line with quantity > 1.
     * We normalize it into instance-based mapping.
     */
    applyExistingRequest(existing) {
        const qtyMap = {};
        (existing.rooms || []).forEach((r) => {
            if (r.roomId && r.quantity && r.quantity > 0) {
                qtyMap[r.roomId] = r.quantity;
            }
        });
        this.roomQuantities = qtyMap;

        const designMap = {};
        let total = 0;

        // helper to generate next index for a roomId
        const nextIndexByRoom = {};
        const getNextIndex = (roomId) => {
            const cur = nextIndexByRoom[roomId] || 0;
            const next = cur + 1;
            nextIndexByRoom[roomId] = next;
            return next;
        };

        (existing.roomDesigns || []).forEach((line) => {
            if (!line.roomId || !line.designId) return;

            const design = (this.allDesigns || []).find((d) => d.id === line.designId);
            const qty = line.quantity && line.quantity > 0 ? line.quantity : 1;

            const price = design && design.basePrice
                ? design.basePrice
                : (line.lineAmount && qty ? line.lineAmount / qty : 0);

            // If stored qty > 1, expand into instances
            for (let i = 0; i < qty; i += 1) {
                const idx = getNextIndex(line.roomId);
                const instanceKey = `${line.roomId}__${idx}`;

                const lineAmount = price * 1;

                designMap[instanceKey] = {
                    roomId: line.roomId,
                    instanceIndex: idx,
                    designId: line.designId,
                    designName: design ? design.name : 'Design',
                    price,
                    quantity: 1,
                    lineAmount,
                    imageUrl: design ? this.resolveImageUrl(design.imageUrl) : null
                };
                total += lineAmount;
            }
        });

        this.roomDesignMap = designMap;
        this.totalBudget = total;

        this.hasExistingRequest =
            Object.keys(qtyMap).length > 0 || Object.keys(designMap).length > 0;

        // set default current instance
        const instanceKeys = Object.keys(designMap);
        if (!this.currentRoomInstanceKey) {
            const allInst = this.roomInstances;
            this.currentRoomInstanceKey = allInst.length ? allInst[0].instanceKey : (instanceKeys.length ? instanceKeys[0] : null);
        }
    }

    // -----------------------------
    // Steps
    // -----------------------------
    get steps() {
        const labels = [
            'Customer',
            'Project Type',
            'Category',
            'Rooms',
            'Plan',
            'Room Designs',
            'Preview Designs',
            'Review'
        ];
        return labels.map((label, index) => {
            const stepNumber = index + 1;
            let cls = 'step-item';
            if (stepNumber === this.currentStep) cls = 'step-item active';
            else if (stepNumber < this.currentStep) cls = 'step-item done';
            return { number: stepNumber, label, cls };
        });
    }

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isStep6() { return this.currentStep === 6; }
    get isStep7() { return this.currentStep === 7; }
    get isStep8() { return this.currentStep === 8; }
    get isFirst() { return this.currentStep === 1; }

    get nextLabel() {
        return this.currentStep === 8 ? (this.isSaving ? 'Saving…' : 'Save') : 'Next';
    }

    // -----------------------------
    // UI options
    // -----------------------------
    get projectTypeOptions() {
        return (this.allProjectTypes || []).map((pt) => ({
            label: pt.name,
            value: pt.id,
            cardClass: pt.id === this.selectedProjectTypeId ? 'choice-card selected' : 'choice-card'
        }));
    }

    get categoryCards() {
        return (this.allCategories || [])
            .filter((c) => c.projectTypeId === this.selectedProjectTypeId)
            .map((c) => ({
                label: c.name,
                value: c.id,
                cardClass: c.id === this.selectedCategoryId ? 'choice-card selected' : 'choice-card'
            }));
    }

    get roomsWithQty() {
        return (this.allRooms || [])
            .filter((r) => r.categoryId === this.selectedCategoryId)
            .map((r) => ({
                ...r,
                quantity: this.roomQuantities[r.id] || 0
            }));
    }

    get planOptions() {
        return (this.allPlanLevels || []).map((lvl) => ({
            label: lvl,
            value: lvl,
            cardClass: lvl === this.selectedPlanLevel ? 'choice-card selected' : 'choice-card'
        }));
    }

    /**
     * ✅ NEW: Expanded room instances list (qty aware)
     * Example:
     *  Bedroom qty=2 -> instanceKey: roomId__1, roomId__2
     */
    get roomInstances() {
        const out = [];
        const roomIds = Object.keys(this.roomQuantities || {});
        roomIds.forEach((roomId) => {
            const qty = this.roomQuantities[roomId] || 0;
            if (qty <= 0) return;

            const room = this.allRooms.find((x) => x.id === roomId);
            const roomName = room ? room.name : roomId;

            for (let i = 1; i <= qty; i += 1) {
                const instanceKey = `${roomId}__${i}`;
                const sel = this.roomDesignMap[instanceKey];

                out.push({
                    instanceKey,
                    roomId,
                    roomName,
                    instanceIndex: i,
                    displayName: qty > 1 ? `${roomName} (${i}/${qty})` : `${roomName}`,
                    selectedDesignName: sel ? sel.designName : 'No design selected',
                    cardClass: instanceKey === this.currentRoomInstanceKey ? 'room-sel-card active' : 'room-sel-card'
                });
            }
        });

        // ensure a current instance is set
        if (!this.currentRoomInstanceKey && out.length) {
            this.currentRoomInstanceKey = out[0].instanceKey;
        }
        return out;
    }

    /**
     * ✅ Designs shown should depend on selected instance roomId + plan level
     */
    get currentRoomDesigns() {
        if (!this.currentRoomInstanceKey) return [];

        const placeholder = 'https://via.placeholder.com/220x140?text=Design';
        const { roomId } = this.parseInstanceKey(this.currentRoomInstanceKey);

        const selectedForInstance = this.roomDesignMap[this.currentRoomInstanceKey];

        return (this.allDesigns || [])
            .filter((d) =>
                d.roomId === roomId &&
                (!this.selectedPlanLevel || d.designLevel === this.selectedPlanLevel)
            )
            .map((d) => {
                const isSelected = selectedForInstance && selectedForInstance.designId === d.id;
                const fullUrl = this.resolveImageUrl(d.imageUrl);

                return {
                    ...d,
                    itemClass: isSelected ? 'design-item-tile selected' : 'design-item-tile',
                    thumbUrl: fullUrl || placeholder,
                    fullImageUrl: fullUrl || placeholder
                };
            });
    }

    /**
     * ✅ Preview tiles now per-instance (so bedroom can appear twice with different design)
     */
    get selectedDesignTiles() {
        const tiles = [];
        const placeholder = 'https://via.placeholder.com/220x140?text=Design';

        (this.roomInstances || []).forEach((inst) => {
            const rd = this.roomDesignMap[inst.instanceKey];
            if (!rd) return;

            const img = this.resolveImageUrl(rd.imageUrl) || placeholder;

            tiles.push({
                instanceKey: inst.instanceKey,
                roomId: inst.roomId,
                roomName: inst.displayName,
                designName: rd.designName,
                imageUrl: img,
                quantity: 1,
                lineAmount: rd.lineAmount || 0
            });
        });

        return tiles;
    }

    get roomsWithDesignCount() {
        return Object.keys(this.roomDesignMap || {}).length;
    }

    get totalRoomQuantity() {
        let total = 0;
        for (const roomId in this.roomQuantities) {
            if (!Object.prototype.hasOwnProperty.call(this.roomQuantities, roomId)) continue;
            const qty = this.roomQuantities[roomId];
            if (qty && qty > 0) total += qty;
        }
        return total;
    }

    // ---------- DISPLAY HELPERS FOR STEP 7/8 ----------
    get selectedPlan() {
        return this.selectedPlanLevel || '';
    }

    get selectedProjectTypeName() {
        const pt = (this.allProjectTypes || []).find((x) => x.id === this.selectedProjectTypeId);
        return pt ? pt.name : '';
    }

    get selectedCategoryName() {
        const cat = (this.allCategories || []).find((x) => x.id === this.selectedCategoryId);
        return cat ? cat.name : '';
    }

    /**
     * Used in STEP 8 template: finalRoomDesignLines.length
     * Must always return an array (never undefined)
     */
    get finalRoomDesignLines() {
        const lines = [];
        (this.selectedDesignTiles || []).forEach((t) => {
            lines.push(`${t.roomName} → ${t.designName}`);
        });
        return lines;
    }

    // -----------------------------
    // Helpers
    // -----------------------------
    parseInstanceKey(instanceKey) {
        const parts = (instanceKey || '').split('__');
        return {
            roomId: parts[0],
            instanceIndex: parts.length > 1 ? parseInt(parts[1], 10) : 1
        };
    }

    /**
     * When qty decreases, remove designs for removed instances.
     */
    syncDesignsWithRoomQty() {
        const nextMap = { ...this.roomDesignMap };

        // remove any instance that exceeds qty
        const qtyMap = this.roomQuantities || {};
        Object.keys(nextMap).forEach((instanceKey) => {
            const { roomId, instanceIndex } = this.parseInstanceKey(instanceKey);
            const max = qtyMap[roomId] || 0;
            if (instanceIndex > max || max <= 0) {
                delete nextMap[instanceKey];
            }
        });

        this.roomDesignMap = nextMap;

        // ensure current instance still valid
        if (this.currentRoomInstanceKey) {
            const { roomId, instanceIndex } = this.parseInstanceKey(this.currentRoomInstanceKey);
            const max = (this.roomQuantities[roomId] || 0);
            if (!max || instanceIndex > max) {
                const inst = this.roomInstances;
                this.currentRoomInstanceKey = inst.length ? inst[0].instanceKey : null;
            }
        }

        this.recalcTotal();
    }

    /**
     * ✅ Default rooms dynamically from Interior_Room__c list for that category.
     * If tomorrow you add new rooms, it will automatically come.
     */
    applyDefaultRoomsForCategory(categoryId) {
        const qtyMap = {};
        (this.allRooms || [])
            .filter((r) => r.categoryId === categoryId)
            .forEach((r) => {
                // If you add Default_Qty__c in future, use it:
                const defaultQty = r.defaultQty && r.defaultQty > 0 ? r.defaultQty : 1;
                qtyMap[r.id] = defaultQty;
            });

        this.roomQuantities = qtyMap;
        this.roomDesignMap = {};
        this.currentRoomInstanceKey = null;
        this.recalcTotal();
    }

    // -----------------------------
    // Handlers
    // -----------------------------
    handleInput(event) {
        const fld = event.target.dataset.field;
        this[fld] = event.target.value;
    }

    handleProjectTypeCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedProjectTypeId = id;

        this.selectedCategoryId = null;
        this.roomQuantities = {};
        this.selectedPlanLevel = null;

        this.roomDesignMap = {};
        this.currentRoomInstanceKey = null;
        this.totalBudget = 0;
    }

    handleCategoryCardClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedCategoryId = id;

        this.selectedPlanLevel = null;
        this.roomDesignMap = {};
        this.currentRoomInstanceKey = null;

        // ✅ AUTO DEFAULT (dynamic)
        if (this.AUTO_DEFAULT_ROOMS) {
            this.applyDefaultRoomsForCategory(id);
        } else {
            this.roomQuantities = {};
            this.recalcTotal();
        }
    }

    handleRoomIncrement(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.roomQuantities[id] || 0;
        this.roomQuantities = { ...this.roomQuantities, [id]: cur + 1 };
        this.syncDesignsWithRoomQty();
    }

    handleRoomDecrement(event) {
        const id = event.currentTarget.dataset.id;
        const cur = this.roomQuantities[id] || 0;
        const next = cur - 1;
        this.roomQuantities = { ...this.roomQuantities, [id]: next > 0 ? next : 0 };
        this.syncDesignsWithRoomQty();
    }

    handlePlanSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedPlanLevel = id;

        // reset designs because plan changed
        this.roomDesignMap = {};
        this.currentRoomInstanceKey = null;
        this.recalcTotal();
    }

    handleRoomSelectForDesign(event) {
        this.currentRoomInstanceKey = event.currentTarget.dataset.id; // instanceKey
    }

    /**
     * ✅ Design pick is PER INSTANCE now
     */
    handleRoomDesignPick(event) {
        const designId = event.currentTarget.dataset.id;
        const design = this.allDesigns.find((x) => x.id === designId);
        if (!design || !this.currentRoomInstanceKey) return;

        const current = this.roomDesignMap[this.currentRoomInstanceKey];

        // toggle off if same selected
        if (current && current.designId === designId) {
            const cloned = { ...this.roomDesignMap };
            delete cloned[this.currentRoomInstanceKey];
            this.roomDesignMap = cloned;
            this.recalcTotal();
            return;
        }

        const fullImg = this.resolveImageUrl(design.imageUrl);
        const price = design.basePrice || 0;

        const { roomId, instanceIndex } = this.parseInstanceKey(this.currentRoomInstanceKey);

        this.roomDesignMap = {
            ...this.roomDesignMap,
            [this.currentRoomInstanceKey]: {
                roomId,
                instanceIndex,
                designId: design.id,
                designName: design.name,
                price,
                quantity: 1,
                lineAmount: price * 1,
                imageUrl: fullImg
            }
        };

        this.recalcTotal();
    }

    /**
     * Remove selected design line (per instance)
     */
    handleRemoveSelected(event) {
        const instanceKey = event.currentTarget.dataset.instancekey;
        const cloned = { ...this.roomDesignMap };
        delete cloned[instanceKey];
        this.roomDesignMap = cloned;
        this.recalcTotal();
    }

    openImageModal(event) {
        event.stopPropagation();
        this.modalImageUrl = event.currentTarget.dataset.img;
        this.modalTitle = event.currentTarget.dataset.title;
        this.isImageModalOpen = true;
    }

    closeImageModal() {
        this.isImageModalOpen = false;
        this.modalImageUrl = null;
        this.modalTitle = null;
    }

    handleImgError(event) {
        // eslint-disable-next-line no-param-reassign
        event.target.src = 'https://via.placeholder.com/220x140?text=No+Img';
    }

    // -----------------------------
    // Next / Prev + Validations
    // -----------------------------
    handleNext() {
        if (this.isSaving) return;

        if (this.currentStep === 1) {
            if (!this.firstName || !this.lastName || !this.email || !this.phone || !this.siteSpace) {
                this.showToast('Missing info', 'First Name, Last Name, Email, Phone and Site Space are required.', 'error');
                return;
            }
        }

        if (this.currentStep === 2 && !this.selectedProjectTypeId) {
            this.showToast('Select project type', 'Please select a project type.', 'error');
            return;
        }

        if (this.currentStep === 3 && !this.selectedCategoryId) {
            this.showToast('Select category', 'Please select a category.', 'error');
            return;
        }

        if (this.currentStep === 4) {
            const hasRoom = Object.values(this.roomQuantities || {}).some((q) => q > 0);
            if (!hasRoom) {
                this.showToast('Select rooms', 'Please add at least one room.', 'error');
                return;
            }

            // optional BHK validation (generic) - if you want to enforce minimum based on category name
            if (this.MIN_ROOMS_FOR_BHK) {
                // keep it simple: at least 1 room exists (already checked)
            }
        }

        if (this.currentStep === 5 && !this.selectedPlanLevel) {
            this.showToast('Select plan', 'Please select a plan/level.', 'error');
            return;
        }

        if (this.currentStep === 6) {
            // ✅ Must select design for EACH INSTANCE
            const missing = (this.roomInstances || []).some((inst) => !this.roomDesignMap[inst.instanceKey]);
            if (missing) {
                this.showToast('Designs missing', 'Please choose a design for every room (including each quantity item).', 'error');
                return;
            }
            this.recalcTotal();
        }

        if (this.currentStep === 7) {
            // Ensure no instance missing design (in case removed in preview)
            const missing = (this.roomInstances || []).some((inst) => !this.roomDesignMap[inst.instanceKey]);
            if (missing) {
                this.showToast(
                    'Design removed',
                    'You removed one of the room designs. Please go back to "Room Designs" and select a design for every room item.',
                    'error'
                );
                this.currentStep = 6;
                return;
            }
        }

        if (this.currentStep < 8) this.currentStep += 1;
        else this.saveData();
    }

    handlePrev() {
        if (this.currentStep > 1) this.currentStep -= 1;
    }

    recalcTotal() {
        let total = 0;
        for (const key in this.roomDesignMap) {
            if (!Object.prototype.hasOwnProperty.call(this.roomDesignMap, key)) continue;
            total += (this.roomDesignMap[key].lineAmount || 0);
        }
        this.totalBudget = total;
    }

    // -----------------------------
    // Save
    // -----------------------------
    saveData() {
        if (this.hasExistingRequest) {
            this.showToast(
                'Lead already submitted',
                'Lead details already submitted. If you have any queries contact Arelia Team.',
                'warning'
            );
            return;
        }

        this.isSaving = true;

        const rooms = [];
        for (const roomId in this.roomQuantities) {
            if (!Object.prototype.hasOwnProperty.call(this.roomQuantities, roomId)) continue;
            const qty = this.roomQuantities[roomId];
            if (qty && qty > 0) rooms.push({ roomId, quantity: qty });
        }

        /**
         * ✅ Save design lines per instance
         * quantity always 1 for each instance.
         * (If Apex wants aggregation later, we can group by roomId+designId)
         */
        const selectedRoomDesigns = [];
        for (const instanceKey in this.roomDesignMap) {
            if (!Object.prototype.hasOwnProperty.call(this.roomDesignMap, instanceKey)) continue;
            const rd = this.roomDesignMap[instanceKey];

            selectedRoomDesigns.push({
                roomId: rd.roomId,
                designId: rd.designId,
                quantity: 1,
                lineAmount: rd.lineAmount
            });
        }

        const payload = {
            leadId: this.leadId,
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            company: this.company,
            address: this.address,
            siteSpace: this.siteSpace,
            description: this.description,
            projectTypeId: this.selectedProjectTypeId,
            categoryId: this.selectedCategoryId,
            planLevel: this.selectedPlanLevel,
            rooms,
            selectedRoomDesigns,
            totalBudget: this.totalBudget,
            quotationType: this.quotationType
        };

        saveRequest({ req: payload })
            .then(() => {
                this.isSaving = false;
                this.showToast(
                    'Project Request Submitted',
                    'Your automatic project details have been captured on the Lead. Our team will review and contact you shortly.',
                    'success'
                );

                if (this.labels.siteUrl) {
                    window.setTimeout(() => {
                        window.location.href = this.labels.siteUrl;
                    }, 1500);
                }
            })
            .catch((err) => {
                this.isSaving = false;
                this.showToast(
                    'Error',
                    err && err.body && err.body.message ? err.body.message : 'Unable to submit project request.',
                    'error'
                );
            });
    }

    // -----------------------------
    // Toast
    // -----------------------------
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}