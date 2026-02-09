public without sharing class AreliaPathController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllStages() {
        List<Map<String, String>> steps = new List<Map<String, String>>();
        
        // --- 1. NEW STEPS ---
        steps.add(new Map<String, String>{ 'label' => 'Opportunity Created', 'value' => 'Opportunity Created' });
        steps.add(new Map<String, String>{ 'label' => 'Enter Architect Data', 'value' => 'Enter Architect Data' });
        steps.add(new Map<String, String>{ 'label' => 'Send Architecture Client Approval', 'value' => 'Send Architecture Client Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Client Architecture Approval', 'value' => 'Client Architecture Approval' });
        steps.add(new Map<String, String>{ 'label' => 'Architecture Manager Approval', 'value' => 'Architecture Manager Approval' });
        
        // NEW STEP ADDED HERE
        steps.add(new Map<String, String>{ 'label' => 'Upload Proforma Invoice', 'value' => 'Upload Proforma Invoice' });

        steps.add(new Map<String, String>{ 'label' => 'Catalogue Link Sent', 'value' => 'Catalogue Link Sent' });
        
        // --- 2. EXISTING STEPS ---
        steps.add(new Map<String, String>{ 'label' => 'Catalogue Received', 'value' => 'Catalogue Received' });
        steps.add(new Map<String, String>{ 'label' => 'Create Payment Terms', 'value' => 'Create Payment Terms' });
        steps.add(new Map<String, String>{ 'label' => 'Specifications & Manager Approval', 'value' => 'Specifications & Payment Terms Manager approval' });
        steps.add(new Map<String, String>{ 'label' => 'Client Agreement Sent', 'value' => 'Client Agreement Sent' });
        steps.add(new Map<String, String>{ 'label' => 'Client Agreement Signed', 'value' => 'Client Agreement Signed' });
        steps.add(new Map<String, String>{ 'label' => 'Tender Invites', 'value' => 'Tender Invites' });
        steps.add(new Map<String, String>{ 'label' => 'Create Vendor Opps', 'value' => 'Create Vendor Opps' });
        steps.add(new Map<String, String>{ 'label' => 'Vendor Agreement Sent', 'value' => 'Vendor Agreement Sent' });
        steps.add(new Map<String, String>{ 'label' => 'Vendor Agreement Signed', 'value' => 'Vendor Agreement Signed' });
        steps.add(new Map<String, String>{ 'label' => 'Closed Won', 'value' => 'Closed Won' });

        // --- 3. CONDITIONAL STEPS ---
        steps.add(new Map<String, String>{ 'label' => 'Negotiation/Review', 'value' => 'Negotiation/Review' });
        steps.add(new Map<String, String>{ 'label' => 'Resumed', 'value' => 'Resumed' });

        return steps;
    }

    @AuraEnabled(cacheable=true)
    public static String getPathStatus(Id oppId) {
        Opportunity opp = [
            SELECT Id, StageName, 
                   Architect_Name__c, 
                   Architecture_Client_Approval_Sent__c,
                   Architecture_Manager_Approval__c,
                   Catalogue_Link_Sent__c,
                   Client_Agreement_Sent__c, 
                   Client_Agreement_Signed__c, 
                   All_Vendors_Agreement_Completed__c, 
                   (SELECT Id, Manager_Approval__c FROM Quotations__r ORDER BY CreatedDate DESC LIMIT 1),
                   (SELECT Id FROM Payment_Terms__r LIMIT 1),
                   (SELECT Id, Vendor_Agreement_Sent__c FROM Vendor_Opportunities__r),
                   (SELECT Id FROM Architecture_Designs__r WHERE Status__c = 'Approved' LIMIT 1),
                   // NEW: Query using the relationship name from your image
                   (SELECT Id FROM Proforma_Invoices__r LIMIT 1)
            FROM Opportunity WHERE Id = :oppId 
            WITH USER_MODE 
            LIMIT 1
        ];

        // 1. Priority Checks
        if (opp.StageName == 'Resumed') {
            return 'Resumed';
        }
        if (opp.StageName == 'Negotiation/Review') {
            return 'Negotiation/Review';
        }

        // 2. Logic Waterfall
        String status = checkInitialStages(opp);
        if (status != null) {
            return status;
        }

        status = checkCatalogueAndPaymentStages(opp);
        if (status != null) {
            return status;
        }

        status = checkAgreementStages(opp);
        if (status != null) {
            return status;
        }

        status = checkVendorAndClosingStages(opp);
        if (status != null) {
            return status;
        }

        return 'Closed Won';
    }

    // --- HELPER METHODS ---

    private static String checkInitialStages(Opportunity opp) {
        // 1. Enter Architect Data
        if (String.isBlank(opp.Architect_Name__c)) {
            return 'Enter Architect Data';
        }

        // 2. Send Architecture Client Approval
        if (opp.Architecture_Client_Approval_Sent__c == false) {
            return 'Send Architecture Client Approval';
        }

        // 3. Client Architecture Approval
        if (opp.Architecture_Designs__r == null || opp.Architecture_Designs__r.isEmpty()) {
            return 'Client Architecture Approval';
        }

        // 4. Architecture Manager Approval
        if (opp.Architecture_Manager_Approval__c == false) {
            return 'Architecture Manager Approval';
        }

        // 5. Upload Proforma Invoice (NEW)
        // Logic: If NO child invoices exist, we stop here.
        if (opp.Proforma_Invoices__r == null || opp.Proforma_Invoices__r.isEmpty()) {
            return 'Upload Proforma Invoice';
        }

        // 6. Catalogue Link Sent
        if (opp.Catalogue_Link_Sent__c == false) {
            return 'Catalogue Link Sent';
        }

        return null; 
    }

    private static String checkCatalogueAndPaymentStages(Opportunity opp) {
        if (opp.Payment_Terms__r == null || opp.Payment_Terms__r.isEmpty()) {
            return 'Catalogue Received'; 
        }
        
        if (opp.Quotations__r != null && !opp.Quotations__r.isEmpty()) {
             if (opp.Quotations__r[0].Manager_Approval__c == false) {
                 return 'Specifications & Payment Terms Manager approval'; 
             }
        } else {
             return 'Create Payment Terms';
        }
        return null;
    }

    private static String checkAgreementStages(Opportunity opp) {
        if (opp.Client_Agreement_Sent__c == false) {
            return 'Client Agreement Sent';
        }
        if (opp.Client_Agreement_Signed__c == false) {
            return 'Client Agreement Signed';
        }
        return null;
    }

    private static String checkVendorAndClosingStages(Opportunity opp) {
        Boolean isVendorSent = false;
        if (opp.Vendor_Opportunities__r != null) {
            for (SObject vo : opp.Vendor_Opportunities__r) {
                if (vo.get('Vendor_Agreement_Sent__c') == true) {
                    isVendorSent = true;
                    break; 
                }
            }
        }
        
        if (isVendorSent == false) {
            return 'Tender Invites'; 
        }
        if (opp.All_Vendors_Agreement_Completed__c == false) {
            return 'Vendor Agreement Signed'; 
        }
        if (opp.StageName != 'Closed Won') {
            return 'Closed Won'; 
        }
        return null;
    }
}