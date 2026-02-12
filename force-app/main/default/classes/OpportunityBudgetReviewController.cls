@SuppressWarnings('PMD.ApexCRUDViolation, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.ApexSOQLInjection')
public with sharing class OpportunityBudgetReviewController {

    private static final String OPP_CUSTOMER_PRIMARY   = 'Budget__c';
    private static final String OPP_CUSTOMER_SECONDARY = 'Estimated_Budget__c';

    private static final String OPP_SUP_PRIMARY        = 'Supervisor_Estimated_Budget__c';
    private static final String OPP_SUP_SECONDARY      = 'Re_Visit_Site_Supervisor_Estimate_Budget__c';

    private static final String OPP_DURATION_PRIMARY   = 'Project_Estimated_Completion_Months__c';
    private static final String OPP_DURATION_SECONDARY = 'ReVisit_Site_Estimated_Completion_Months__c';

    private static final String ARCH_OBJ           = 'Architecture_Design__c';
    private static final String ARCH_LOOKUP_TO_OPP = 'Opportunity__c';
    private static final String ARCH_NAME_FIELD    = 'Name';
    private static final String ARCH_AMOUNT_FIELD  = 'Architecture_Budget__c';
    private static final String ARCH_CLIENT_STATUS_FIELD  = 'Status__c';
    private static final String ARCH_MANAGER_APPROVAL_FLD  = 'Manager_Approval__c';

    private static final String TERM_OBJ            = 'Payment_Term__c';
    private static final String TERM_LOOKUP_TO_OPP  = 'Opportunity__c';
    private static final String TERM_LABEL_FIELD    = 'Term_Label__c';
    private static final String TERM_PERCENT_FIELD  = 'Percentage__c';
    private static final String TERM_DUE_DATE_FIELD = 'Due_Date__c';
    private static final String TERM_RECEIVED_FIELD = 'Payment_Received__c';

    public class ArchitectureRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String clientApproval;
        @AuraEnabled public Boolean managerApproval;
    }

    public class PaymentTermRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String termLabel;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public Boolean paymentReceived;
    }

    public class BudgetReviewResponseDTO {
        @AuraEnabled public Decimal customerBudget;
        @AuraEnabled public String customerBudgetSource;

        @AuraEnabled public Decimal supervisorBudget;
        @AuraEnabled public String supervisorBudgetSource;

        @AuraEnabled public Decimal finalBudget;

        @AuraEnabled public String estimatedDuration;
        @AuraEnabled public String durationSource;

        @AuraEnabled public List<ArchitectureRowDTO> architectureRows;
        @AuraEnabled public List<PaymentTermRowDTO> paymentTerms;
    }

    public class BudgetReviewSaveRequestDTO {
        @AuraEnabled public List<ArchitectureRowDTO> architectureRows;
        @AuraEnabled public List<PaymentTermRowDTO> paymentTerms;
    }

    // =========================
    // GET (✅ Re-visit wins ALWAYS)
    // =========================
    @AuraEnabled(cacheable=true)
    public static BudgetReviewResponseDTO getBudgetReview(Id opportunityId) {
        if (opportunityId == null) {return null;}

        Opportunity opp = queryOpportunity(opportunityId);

        // Customer: keep primary-first (as you had)
        Decimal custPrimary   = (Decimal)opp.get(OPP_CUSTOMER_PRIMARY);
        Decimal custSecondary = (Decimal)opp.get(OPP_CUSTOMER_SECONDARY);

        Decimal customerBudget;
        String customerSource;
        if (custPrimary != null) { customerBudget = custPrimary; customerSource = OPP_CUSTOMER_PRIMARY; }
        else if (custSecondary != null) { customerBudget = custSecondary; customerSource = OPP_CUSTOMER_SECONDARY; }
        else { customerBudget = null; customerSource = OPP_CUSTOMER_PRIMARY; }

        // ✅ Supervisor: secondary (Re-Visit) FIRST always
        Decimal supPrimary   = (Decimal)opp.get(OPP_SUP_PRIMARY);
        Decimal supSecondary = (Decimal)opp.get(OPP_SUP_SECONDARY);

        Decimal supervisorBudget;
        String supervisorSource;
        if (supSecondary != null) { supervisorBudget = supSecondary; supervisorSource = OPP_SUP_SECONDARY; }
        else if (supPrimary != null) { supervisorBudget = supPrimary; supervisorSource = OPP_SUP_PRIMARY; }
        else { supervisorBudget = null; supervisorSource = OPP_SUP_SECONDARY; }

        // ✅ Duration: secondary (Re-Visit) FIRST always
        String durPrimary   = opp.get(OPP_DURATION_PRIMARY) == null ? null : String.valueOf(opp.get(OPP_DURATION_PRIMARY));
        String durSecondary = opp.get(OPP_DURATION_SECONDARY) == null ? null : String.valueOf(opp.get(OPP_DURATION_SECONDARY));

        String duration;
        String durSource;
        if (String.isNotBlank(durSecondary)) { duration = durSecondary; durSource = OPP_DURATION_SECONDARY; }
        else if (String.isNotBlank(durPrimary)) { duration = durPrimary; durSource = OPP_DURATION_PRIMARY; }
        else { duration = null; durSource = OPP_DURATION_SECONDARY; }

        BudgetReviewResponseDTO dto = new BudgetReviewResponseDTO();
        dto.customerBudget = customerBudget;
        dto.customerBudgetSource = customerSource;

        dto.supervisorBudget = supervisorBudget;
        dto.supervisorBudgetSource = supervisorSource;

        dto.finalBudget = supervisorBudget;

        dto.estimatedDuration = duration;
        dto.durationSource = durSource;

        dto.architectureRows = queryArchitectureRows(opportunityId);
        dto.paymentTerms = queryPaymentTerms(opportunityId);
        return dto;
    }

    // =========================
    // SAVE (Children only)
    // =========================
    @AuraEnabled
    public static BudgetReviewResponseDTO saveChildRows(Id opportunityId, BudgetReviewSaveRequestDTO req) {
        if (opportunityId == null || req == null) {return getBudgetReview(opportunityId);}
        updateArchitectureRows(req.architectureRows);
        updatePaymentTerms(req.paymentTerms);
        return getBudgetReview(opportunityId);
    }

    // =========================
    // Queries
    // =========================
    private static Opportunity queryOpportunity(Id opportunityId) {
        String soql =
            'SELECT Id,' +
            ' ' + OPP_CUSTOMER_PRIMARY + ',' +
            ' ' + OPP_CUSTOMER_SECONDARY + ',' +
            ' ' + OPP_SUP_PRIMARY + ',' +
            ' ' + OPP_SUP_SECONDARY + ',' +
            ' ' + OPP_DURATION_PRIMARY + ',' +
            ' ' + OPP_DURATION_SECONDARY +
            ' FROM Opportunity WHERE Id = :opportunityId LIMIT 1';
        return Database.query(soql);
    }

    private static List<ArchitectureRowDTO> queryArchitectureRows(Id opportunityId) {
        List<ArchitectureRowDTO> rows = new List<ArchitectureRowDTO>();

        String soql =
            'SELECT Id,' + ARCH_NAME_FIELD + ',' + ARCH_AMOUNT_FIELD + ',' +
            ARCH_CLIENT_STATUS_FIELD + ',' + ARCH_MANAGER_APPROVAL_FLD +
            ' FROM ' + ARCH_OBJ +
            ' WHERE ' + ARCH_LOOKUP_TO_OPP + ' = :opportunityId' +
            ' ORDER BY CreatedDate ASC';

        for (SObject s : Database.query(soql)) {
            ArchitectureRowDTO r = new ArchitectureRowDTO();
            r.id = (Id)s.get('Id');
            r.name = (String)s.get(ARCH_NAME_FIELD);
            r.amount = (Decimal)s.get(ARCH_AMOUNT_FIELD);
            r.clientApproval = (String)s.get(ARCH_CLIENT_STATUS_FIELD);
            r.managerApproval = (Boolean)s.get(ARCH_MANAGER_APPROVAL_FLD);
            rows.add(r);
        }
        return rows;
    }

    private static List<PaymentTermRowDTO> queryPaymentTerms(Id opportunityId) {
        List<PaymentTermRowDTO> rows = new List<PaymentTermRowDTO>();

        String soql =
            'SELECT Id,' + TERM_LABEL_FIELD + ',' + TERM_PERCENT_FIELD + ',' +
            TERM_DUE_DATE_FIELD + ',' + TERM_RECEIVED_FIELD +
            ' FROM ' + TERM_OBJ +
            ' WHERE ' + TERM_LOOKUP_TO_OPP + ' = :opportunityId' +
            ' ORDER BY ' + TERM_DUE_DATE_FIELD + ' ASC NULLS LAST, CreatedDate ASC';

        for (SObject s : Database.query(soql)) {
            PaymentTermRowDTO p = new PaymentTermRowDTO();
            p.id = (Id)s.get('Id');
            p.termLabel = (String)s.get(TERM_LABEL_FIELD);
            p.percentage = (Decimal)s.get(TERM_PERCENT_FIELD);
            p.dueDate = (Date)s.get(TERM_DUE_DATE_FIELD);
            p.paymentReceived = (Boolean)s.get(TERM_RECEIVED_FIELD);
            rows.add(p);
        }
        return rows;
    }

    private static void updateArchitectureRows(List<ArchitectureRowDTO> rows) {
        if (rows == null || rows.isEmpty()) {return;}

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(ARCH_OBJ);
        List<SObject> updates = new List<SObject>();

        for (ArchitectureRowDTO r : rows) {
            if (r == null || r.id == null || r.amount == null) {continue;}
            SObject s = sType.newSObject();
            s.put('Id', r.id);
            s.put(ARCH_AMOUNT_FIELD, r.amount);
            updates.add(s);
        }
        if (!updates.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, updates);
            List<SObject> sanitized = decision.getRecords();
            if (!sanitized.isEmpty()) {update sanitized;}
        }
    }

    private static void updatePaymentTerms(List<PaymentTermRowDTO> rows) {
        if (rows == null || rows.isEmpty()) {return;}

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(TERM_OBJ);
        List<SObject> updates = new List<SObject>();

        for (PaymentTermRowDTO p : rows) {
            if (p == null || p.id == null) {continue;}
            SObject s = sType.newSObject();
            s.put('Id', p.id);

            if (p.termLabel != null) {s.put(TERM_LABEL_FIELD, p.termLabel);}
            if (p.percentage != null) {s.put(TERM_PERCENT_FIELD, p.percentage);}
            if (p.dueDate != null) {s.put(TERM_DUE_DATE_FIELD, p.dueDate);}
            if (p.paymentReceived != null) {s.put(TERM_RECEIVED_FIELD, p.paymentReceived);}

            updates.add(s);
        }
        if (!updates.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, updates);
            List<SObject> sanitized = decision.getRecords();
            if (!sanitized.isEmpty()) {update sanitized;}
        }
    }
}
