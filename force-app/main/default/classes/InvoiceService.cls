@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation')
public with sharing class InvoiceService {

    // =========================
    // DTOs
    // =========================
    public class HeaderDTO {
        @AuraEnabled public String  clientName;
        @AuraEnabled public String  phone;
        @AuraEnabled public String  clientAddress;
        @AuraEnabled public Date    invoiceDate;
        @AuraEnabled public String  invoiceNo;
        @AuraEnabled public Decimal gstPercent;
    }

    public class LineDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String category;
        @AuraEnabled public String item;
        @AuraEnabled public String brand;
        @AuraEnabled public String explanation;

        // WOOD-LIKE (WOOD + CIVIL WORK)
        @AuraEnabled public Decimal l;
        @AuraEnabled public Decimal h;
        @AuraEnabled public Decimal qty;

        // ELECTRICAL
        @AuraEnabled public String  electricalMode; // COILS or QTY
        @AuraEnabled public Decimal coils;
        @AuraEnabled public Decimal meters;

        // COMMON
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal amount; // ✅ used for OTHER as manual amount
    }

    public class SectionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String sectionName;
        @AuraEnabled public String sectionType; // picklist value
        @AuraEnabled public List<LineDTO> lines;
        @AuraEnabled public Decimal subtotal;
    }

    public class MaterialDTO {
        @AuraEnabled public String  material;
        @AuraEnabled public String  brand;
        @AuraEnabled public String  grade;
        @AuraEnabled public Integer sortOrder;
    }

    public class NotIncludedDTO {
        @AuraEnabled public String  text;
        @AuraEnabled public Integer sortOrder;
    }

    public class PayloadDTO {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Id existingInvoiceId;

        @AuraEnabled public HeaderDTO header;
        @AuraEnabled public List<SectionDTO> sections;

        @AuraEnabled public List<MaterialDTO> materials;
        @AuraEnabled public List<NotIncludedDTO> notIncluded;

        @AuraEnabled public Decimal total;
        @AuraEnabled public Decimal gstAmount;
        @AuraEnabled public Decimal grandTotal;
    }

    public class InitDTO {
        @AuraEnabled public Id invoiceId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer versionNo;

        @AuraEnabled public HeaderDTO header;
        @AuraEnabled public List<SectionDTO> sections;
        @AuraEnabled public List<MaterialDTO> materials;
        @AuraEnabled public List<NotIncludedDTO> notIncluded;
    }

    // =========================
    // INIT
    // =========================
    @AuraEnabled(cacheable=true)
    public static InitDTO init(Id opportunityId) {
        InitDTO resp = new InitDTO();
        if (opportunityId == null) return resp;

        Invoice__c inv = findDraftOrLatestSubmitted(opportunityId);
        if (inv == null) return resp;

        resp.invoiceId = inv.Id;
        resp.status = inv.Status__c;
        resp.versionNo = (inv.Version_No__c == null) ? null : Integer.valueOf(inv.Version_No__c);

        resp.header = new HeaderDTO();
        resp.header.clientName    = inv.Client_Name__c;
        resp.header.phone         = inv.Phone__c;
        resp.header.clientAddress = inv.Address__c;
        resp.header.invoiceDate   = inv.Invoice_Date__c;
        resp.header.invoiceNo     = inv.Invoice_No__c;
        resp.header.gstPercent    = inv.GST_Percent__c;

        List<Invoice_Line__c> dbLines = [
            SELECT Is_Section__c, Section_Name__c, Section_Type__c,
                   Item__c, Category__c, Brand__c, Explanation__c,
                   L__c, H__c, Qty__c, Coils__c, Meters__c, Electrical_Mode__c,
                   Rate__c, Amount__c, Sort_Order__c, Area_Sqft__c
            FROM Invoice_Line__c
            WHERE Invoice__c = :inv.Id
            ORDER BY Sort_Order__c
        ];

        resp.sections = toSections(dbLines);

        resp.materials = new List<MaterialDTO>();
        for (Invoice_Material__c m : [
            SELECT Material__c, Brand__c, Grade__c, Sort_Order__c
            FROM Invoice_Material__c
            WHERE Invoice__c = :inv.Id
            ORDER BY Sort_Order__c
        ]) {
            MaterialDTO dto = new MaterialDTO();
            dto.material = m.Material__c;
            dto.brand = m.Brand__c;
            dto.grade = m.Grade__c;
            dto.sortOrder = (m.Sort_Order__c == null) ? null : Integer.valueOf(m.Sort_Order__c);
            resp.materials.add(dto);
        }

        resp.notIncluded = new List<NotIncludedDTO>();
        for (Invoice_Not_Included__c n : [
            SELECT Text__c, Sort_Order__c
            FROM Invoice_Not_Included__c
            WHERE Invoice__c = :inv.Id
            ORDER BY Sort_Order__c
        ]) {
            NotIncludedDTO dto = new NotIncludedDTO();
            dto.text = n.Text__c;
            dto.sortOrder = (n.Sort_Order__c == null) ? null : Integer.valueOf(n.Sort_Order__c);
            resp.notIncluded.add(dto);
        }

        return resp;
    }

    // =========================
    // JSON endpoints
    // =========================
    @AuraEnabled
    public static Id saveDraftJson(String payloadJson) {
        PayloadDTO p = parsePayload(payloadJson);
        return saveDraft(p);
    }

    @AuraEnabled
    public static Id submitJson(String payloadJson) {
        PayloadDTO payload = (PayloadDTO) JSON.deserialize(payloadJson, PayloadDTO.class);
        validate(payload);

        Opportunity o = [
            SELECT Id
            FROM Opportunity
            WHERE Id = :payload.opportunityId
            FOR UPDATE
        ];

        if (payload.existingInvoiceId != null) {

            List<Invoice__c> invList = [
                SELECT Id, Status__c, Opportunity__c
                FROM Invoice__c
                WHERE Id = :payload.existingInvoiceId
                FOR UPDATE
            ];

            if (invList.isEmpty()) throw new AuraHandledException('Draft invoice not found.');

            Invoice__c inv = invList[0];

            if (inv.Opportunity__c != payload.opportunityId) {
                throw new AuraHandledException('Draft invoice does not belong to this Opportunity.');
            }

            if (inv.Status__c == 'Submitted') return inv.Id;

            inv.Status__c = 'Submitted';
            applyHeaderAndTotals(inv, payload);
            update inv;

            replaceChildren(inv.Id, payload);

            System.enqueueJob(new InvoicePdfJob(inv.Id));
            return inv.Id;
        }

        Invoice__c newInv = new Invoice__c();
        newInv.Opportunity__c = payload.opportunityId;
        newInv.Status__c = 'Submitted';
        applyHeaderAndTotals(newInv, payload);
        insert newInv;

        replaceChildren(newInv.Id, payload);
        System.enqueueJob(new InvoicePdfJob(newInv.Id));

        return newInv.Id;
    }

    private static PayloadDTO parsePayload(String payloadJson) {
        if (String.isBlank(payloadJson)) throw new AuraHandledException('PayloadJson is missing.');
        PayloadDTO p;
        try {
            p = (PayloadDTO) JSON.deserialize(payloadJson, PayloadDTO.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Payload parse failed: ' + ex.getMessage());
        }
        if (p == null || p.opportunityId == null) throw new AuraHandledException('OpportunityId is required.');

        if (p.header == null) p.header = new HeaderDTO();
        if (p.sections == null) p.sections = new List<SectionDTO>();
        if (p.materials == null) p.materials = new List<MaterialDTO>();
        if (p.notIncluded == null) p.notIncluded = new List<NotIncludedDTO>();
        return p;
    }

    // =========================
    // SAVE DRAFT
    // =========================
    public static Id saveDraft(PayloadDTO payload) {
        validate(payload);

        Id targetId = payload.existingInvoiceId;

        if (targetId == null) {
            List<Invoice__c> drafts = [
                SELECT Id
                FROM Invoice__c
                WHERE Opportunity__c = :payload.opportunityId
                  AND Status__c = 'Draft'
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!drafts.isEmpty()) targetId = drafts[0].Id;
        }

        Boolean isInsert = (targetId == null);

        Invoice__c inv = isInsert ? new Invoice__c() : new Invoice__c(Id = targetId);
        inv.Opportunity__c = payload.opportunityId;
        inv.Status__c = 'Draft';
        applyHeaderAndTotals(inv, payload);

        if (isInsert) insert inv;
        else update inv;

        replaceChildren(inv.Id, payload);
        return inv.Id;
    }

    // =========================
    // VALIDATION + TOTALS
    // =========================
    private static void validate(PayloadDTO p) {
        if (p == null || p.opportunityId == null) throw new AuraHandledException('OpportunityId is required.');
        if (p.header == null) p.header = new HeaderDTO();
        if (p.sections == null) p.sections = new List<SectionDTO>();
        if (p.materials == null) p.materials = new List<MaterialDTO>();
        if (p.notIncluded == null) p.notIncluded = new List<NotIncludedDTO>();
    }

    private static void applyHeaderAndTotals(Invoice__c inv, PayloadDTO p) {
        inv.Client_Name__c = p.header.clientName;
        inv.Phone__c = p.header.phone;
        inv.Address__c = p.header.clientAddress;
        inv.Invoice_Date__c = p.header.invoiceDate;
        inv.Invoice_No__c = p.header.invoiceNo;

        inv.GST_Percent__c = p.header.gstPercent;
        inv.Total__c = p.total;
        inv.GST_Amount__c = p.gstAmount;
        inv.Grand_Total__c = p.grandTotal;
    }

    // =========================
    // CANONICAL TYPE
    // WOOD + CIVIL WORK => WOOD
    // ELECTRICAL => ELECTRICAL
    // OTHER => OTHER
    // =========================
    private static String canonType(String raw) {
        String t = String.isBlank(raw) ? '' : raw.trim().toUpperCase();
        if (t == 'WOOD' || t.contains('WOOD')) return 'WOOD';
        if (t.contains('ELECTRIC')) return 'ELECTRICAL';
        if (t.contains('CIVIL')) return 'WOOD';     // ✅ civil behaves like wood
        if (t.contains('OTHER')) return 'OTHER';
        return 'OTHER';
    }

    private static Decimal nz(Decimal d) { return d == null ? 0 : d; }

    // =========================
    // CHILD REPLACE
    // =========================
    private static void replaceChildren(Id invoiceId, PayloadDTO p) {
        delete [SELECT Id FROM Invoice_Line__c WHERE Invoice__c = :invoiceId];
        delete [SELECT Id FROM Invoice_Material__c WHERE Invoice__c = :invoiceId];
        delete [SELECT Id FROM Invoice_Not_Included__c WHERE Invoice__c = :invoiceId];

        List<Invoice_Line__c> outLines = new List<Invoice_Line__c>();
        Integer sortNo = 1;

        for (SectionDTO s : p.sections) {

            String stPick  = String.isBlank(s.sectionType) ? 'Other Works' : s.sectionType;
            String stCanon = canonType(stPick);

            outLines.add(new Invoice_Line__c(
                Invoice__c      = invoiceId,
                Sort_Order__c   = sortNo++,
                Is_Section__c   = true,
                Section_Name__c = s.sectionName,
                Section_Type__c = stPick
            ));

            if (s.lines == null) continue;

            for (LineDTO l : s.lines) {
                Invoice_Line__c rec = new Invoice_Line__c();
                rec.Invoice__c = invoiceId;
                rec.Sort_Order__c = sortNo++;
                rec.Is_Section__c = false;

                rec.Section_Name__c = s.sectionName;
                rec.Section_Type__c = stPick;

                rec.Category__c = l.category;
                rec.Item__c = l.item;
                rec.Brand__c = l.brand;
                rec.Explanation__c = l.explanation;

                if (stCanon == 'WOOD') {
                    rec.L__c = l.l;
                    rec.H__c = l.h;
                    rec.Qty__c = l.qty;
                    rec.Rate__c = l.rate;

                    Decimal area = ((nz(l.l) * nz(l.h) * nz(l.qty)) / 144);
                    rec.Area_Sqft__c = area.setScale(2);
                    rec.Amount__c = (area * nz(l.rate)).setScale(2);
                }
                else if (stCanon == 'ELECTRICAL') {
                    String mode = String.isBlank(l.electricalMode) ? 'QTY' : l.electricalMode.trim().toUpperCase();
                    if (mode != 'COILS' && mode != 'QTY') mode = 'QTY';
                    rec.Electrical_Mode__c = mode;
                    rec.Rate__c = l.rate;

                    if (mode == 'COILS') {
                        rec.Coils__c = l.coils;
                        rec.Meters__c = l.meters;
                        rec.Qty__c = null;
                        rec.Amount__c = (nz(l.meters) * nz(l.rate)).setScale(2);
                    } else {
                        rec.Coils__c = null;
                        rec.Meters__c = null;
                        rec.Qty__c = l.qty;
                        rec.Amount__c = (nz(l.qty) * nz(l.rate)).setScale(2);
                    }
                }
                else {
                    // ✅ OTHER WORKS: manual amount
                    rec.Rate__c = null;
                    rec.L__c = null; rec.H__c = null; rec.Qty__c = null;
                    rec.Coils__c = null; rec.Meters__c = null; rec.Electrical_Mode__c = null;
                    rec.Area_Sqft__c = null;
                    rec.Amount__c = nz(l.amount).setScale(2);
                }

                outLines.add(rec);
            }
        }

        if (!outLines.isEmpty()) insert outLines;

        List<Invoice_Material__c> mats = new List<Invoice_Material__c>();
        Integer mc = 1;
        for (MaterialDTO m : p.materials) {
            mats.add(new Invoice_Material__c(
                Invoice__c = invoiceId,
                Sort_Order__c = (m.sortOrder != null ? m.sortOrder : mc++),
                Material__c = m.material,
                Brand__c = m.brand,
                Grade__c = m.grade
            ));
        }
        if (!mats.isEmpty()) insert mats;

        List<Invoice_Not_Included__c> ni = new List<Invoice_Not_Included__c>();
        Integer nc = 1;
        for (NotIncludedDTO n : p.notIncluded) {
            ni.add(new Invoice_Not_Included__c(
                Invoice__c = invoiceId,
                Sort_Order__c = (n.sortOrder != null ? n.sortOrder : nc++),
                Text__c = n.text
            ));
        }
        if (!ni.isEmpty()) insert ni;
    }

    // =========================
    // HELPERS
    // =========================
    private static Invoice__c findDraftOrLatestSubmitted(Id oppId) {
        List<Invoice__c> drafts = [
            SELECT Id, Status__c, Version_No__c, Client_Name__c, Phone__c, Address__c,
                   Invoice_Date__c, Invoice_No__c, GST_Percent__c
            FROM Invoice__c
            WHERE Opportunity__c = :oppId AND Status__c = 'Draft'
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!drafts.isEmpty()) return drafts[0];

        List<Invoice__c> latest = [
            SELECT Id, Status__c, Version_No__c, Client_Name__c, Phone__c, Address__c,
                   Invoice_Date__c, Invoice_No__c, GST_Percent__c
            FROM Invoice__c
            WHERE Opportunity__c = :oppId AND Status__c = 'Submitted'
            ORDER BY Version_No__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        return latest.isEmpty() ? null : latest[0];
    }

    private static List<SectionDTO> toSections(List<Invoice_Line__c> dbLines) {
        List<SectionDTO> secs = new List<SectionDTO>();
        SectionDTO current;

        for (Invoice_Line__c l : dbLines) {
            if (l.Is_Section__c) {
                current = new SectionDTO();
                current.id = String.valueOf(l.Id);
                current.sectionName = l.Section_Name__c;
                current.sectionType = String.isBlank(l.Section_Type__c) ? 'Other Works' : l.Section_Type__c;
                current.lines = new List<LineDTO>();
                current.subtotal = 0;
                secs.add(current);
                continue;
            }
            if (current == null) continue;

            LineDTO dto = new LineDTO();
            dto.id = String.valueOf(l.Id);
            dto.category = l.Category__c;
            dto.item = l.Item__c;
            dto.brand = l.Brand__c;
            dto.explanation = l.Explanation__c;

            dto.l = l.L__c;
            dto.h = l.H__c;
            dto.qty = l.Qty__c;

            dto.electricalMode = l.Electrical_Mode__c;
            dto.coils = l.Coils__c;
            dto.meters = l.Meters__c;

            dto.rate = l.Rate__c;
            dto.amount = l.Amount__c;

            current.lines.add(dto);
            current.subtotal += (l.Amount__c == null ? 0 : l.Amount__c);
        }

        for (SectionDTO s : secs) s.subtotal = (s.subtotal == null ? 0 : s.subtotal).setScale(2);
        return secs;
    }
}
