public without sharing class AreliaPathController {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllStages() {
        List<Map<String, String>> steps = new List<Map<String, String>>();
        steps.add(new Map<String, String>{ 'label' => 'Catalogue Sent', 'value' => 'Catalogue Sent' });
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

        // --- NEW STAGES ---
        steps.add(new Map<String, String>{ 'label' => 'Negotiation/Review', 'value' => 'Negotiation/Review' });
        steps.add(new Map<String, String>{ 'label' => 'Resumed', 'value' => 'Resumed' });

        return steps;
    }

    @AuraEnabled(cacheable=true)
    public static String getPathStatus(Id oppId) {
        // FIX: Added WITH USER_MODE for CRUD/FLS Check
        Opportunity opp = [
            SELECT Id, StageName, Client_Agreement_Sent__c, Client_Agreement_Signed__c, All_Vendors_Agreement_Completed__c, 
                   (SELECT Id, Manager_Approval__c FROM Quotations__r ORDER BY CreatedDate DESC LIMIT 1),
                   (SELECT Id FROM Payment_Terms__r LIMIT 1),
                   (SELECT Id, Vendor_Agreement_Sent__c FROM Vendor_Opportunities__r)
            FROM Opportunity 
            WHERE Id = :oppId 
            WITH USER_MODE
            LIMIT 1
        ];

        // 1. Check Priority Stages (Negotiation/Resumed)
        String priorityStage = getPriorityStage(opp);
        if (priorityStage != null) {
            return priorityStage;
        }

        // 2. Check Standard Pipeline Stages
        return getStandardPipelineStage(opp);
    }

    // Helper: Checks for Stages that override the standard linear flow
    private static String getPriorityStage(Opportunity opp) {
        if (opp.StageName == 'Resumed') {
            return 'Resumed';
        }
        if (opp.StageName == 'Negotiation/Review') {
            return 'Negotiation/Review';
        }
        return null;
    }

    // Helper: Checks the standard linear flow
    // FIX: Extracted logic to reduce Cognitive Complexity of main method
    private static String getStandardPipelineStage(Opportunity opp) {
        // 1. Catalogue Sent
        if (opp.Quotations__r == null || opp.Quotations__r.isEmpty()) {
            return 'Catalogue Sent'; 
        }

        // 2. Catalogue Received
        if (opp.Payment_Terms__r == null || opp.Payment_Terms__r.isEmpty()) {
            return 'Create Payment Terms'; 
        }

        // 3. Create Payment Terms
        if (opp.Quotations__r[0].Manager_Approval__c == false) {
            return 'Specifications & Payment Terms Manager approval'; 
        }

        // 4. Manager Approval
        if (opp.Client_Agreement_Sent__c == false) {
            return 'Client Agreement Sent';
        }

        // 5. Client Agreement Sent
        if (opp.Client_Agreement_Signed__c == false) {
            return 'Client Agreement Signed';
        }

        // 6. Client Agreement Signed (Check Vendor Logic)
        if (!hasSentVendorAgreement(opp)) {
            return 'Tender Invites'; 
        }

        // 7. Vendor Agreement Sent
        if (opp.All_Vendors_Agreement_Completed__c == false) {
            return 'Vendor Agreement Signed'; 
        }

        // 8. Default fallback
        return 'Closed Won';
    }

    // Helper: Iterates through child records to check if ANY vendor agreement was sent
    private static Boolean hasSentVendorAgreement(Opportunity opp) {
        if (opp.Vendor_Opportunities__r != null) {
            for (SObject vo : opp.Vendor_Opportunities__r) {
                if (vo.get('Vendor_Agreement_Sent__c') == true) {
                    return true;
                }
            }
        }
        return false;
    }
}