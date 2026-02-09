@IsTest
public class AreliaPathControllerTest {

    @TestSetup
    static void setup() {
        // 1. Create Supervisor as SYSTEM ADMINISTRATOR
        // We do this manually to ensure they have full permissions on the Project__c object,
        // avoiding the "TRANSFER_REQUIRES_READ" flow error during ownership transfer.
        
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User u = new User(
            Alias = 'pathUser', // Short alias (<8 chars)
            Email = 'pathUser@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = adminProfile.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'pathUser' + DateTime.now().getTime() + '@testorg.com'
        );
        insert u;

        // 2. Create Opportunity
        // Wrap in System.runAs to avoid MIXED_DML_OPERATION (User + Opp)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = TestDataUtility.createOpportunity('Path Test Opp', u.Id);
            
            // Ensure all flags start as false/null to test the very first stage cleanly
            opp.Architecture_Client_Approval_Sent__c = false;
            opp.Architecture_Manager_Approval__c = false;
            opp.Catalogue_Link_Sent__c = false;
            opp.Client_Agreement_Sent__c = false;
            opp.Client_Agreement_Signed__c = false;
            opp.All_Vendors_Agreement_Completed__c = false;
            update opp;
        }
    }

    // ==========================================
    // 1. Test Metadata (Steps List)
    // ==========================================
    @IsTest
    static void testGetAllStages() {
        Test.startTest();
        List<Map<String, String>> stages = AreliaPathController.getAllStages();
        Test.stopTest();

        // The controller defines 17 stages
        Assert.areEqual(17, stages.size(), 'Should return all 17 defined stages from the metadata list');
        
        // Verify a specific stage exists
        Boolean foundNewStage = false;
        for (Map<String, String> stage : stages) {
            if (stage.get('value') == 'Send Architecture Client Approval') {
                foundNewStage = true;
                break;
            }
        }
        Assert.isTrue(foundNewStage, 'The list should contain the specific stage "Send Architecture Client Approval"');
    }

    // ==========================================
    // 2. Test Priority Overrides (Resumed/Negotiation)
    // ==========================================
    @IsTest
    static void testPathStatusOverrides() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Satisfy Validation Rule: "Stage cannot be set to 'Resumed' until All Vendors Agreement Completed is checked."
        opp.All_Vendors_Agreement_Completed__c = true;

        // Test Resumed
        opp.StageName = 'Resumed';
        update opp;
        
        String status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Resumed', status, 'Status should be "Resumed" when Opportunity Stage is "Resumed", overriding other logic');

        // Test Negotiation
        opp.StageName = 'Negotiation/Review';
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Negotiation/Review', status, 'Status should be "Negotiation/Review" when Opportunity Stage is "Negotiation/Review"');
    }

    // ==========================================
    // 3. Test The "Waterfall" Logic Sequence
    // ==========================================
    @IsTest
    static void testPathLogicSequence() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        String status;

        Test.startTest();

        // --- STEP 1: Initial State ---
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Send Architecture Client Approval', status, 'Initial status should be "Send Architecture Client Approval" when no flags are set');

        // --- STEP 2: Architecture Sent ---
        opp.Architecture_Client_Approval_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Architecture Approval', status, 'Status should advance to "Client Architecture Approval" after approval sent flag is true');

        // --- STEP 3: Architecture Approved ---
        // Utility requires a File first
        ContentVersion cv = TestDataUtility.createContentVersion('Arch Design File', 'Content');
        
        // Use Utility to create Design
        TestDataUtility.createArchitectureDesign(opp.Id, cv.Id, 'Approved');
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Architecture Manager Approval', status, 'Status should advance to "Architecture Manager Approval" after design is approved');

        // --- STEP 4: Manager Approval ---
        opp.Architecture_Manager_Approval__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Catalogue Link Sent', status, 'Status should advance to "Catalogue Link Sent" after manager approval is true');

        // --- STEP 5: Catalogue Link Sent ---
        opp.Catalogue_Link_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Catalogue Received', status, 'Status should advance to "Catalogue Received" after catalogue link sent flag is true');

        // --- STEP 6: Payment Terms Created ---
        // Use Utility
        TestDataUtility.createPaymentTerm(opp.Id, '50% Advance', 50.00);
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Create Payment Terms', status, 'Status should advance to "Create Payment Terms" after terms are created');

        // --- STEP 7: Quotation Created (Unapproved) ---
        // Use Utility
        Quotation__c quote = TestDataUtility.createQuotation(opp.Id, 'Test Quote'); 
        quote.Manager_Approval__c = false; 
        update quote;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Specifications & Payment Terms Manager approval', status, 'Status should correspond to manager approval pending when unapproved quote exists');

        // --- STEP 8: Quotation Approved ---
        quote.Manager_Approval__c = true;
        update quote;
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Agreement Sent', status, 'Status should advance to "Client Agreement Sent" after quote is approved');

        // --- STEP 9: Agreement Sent ---
        opp.Client_Agreement_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Agreement Signed', status, 'Status should advance to "Client Agreement Signed" after agreement sent flag is true');

        // --- STEP 10: Agreement Signed ---
        opp.Client_Agreement_Signed__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Tender Invites', status, 'Status should advance to "Tender Invites" after agreement signed flag is true');

        // --- STEP 11: Vendor Agreement Sent ---
        // Use Utility to create Vendor
        Vendor__c v = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'v@test.com');
        
        // Use Utility to create Vendor Opportunity
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, v.Id, 'Active');
        
        // Manually update the flag the controller checks
        vo.Vendor_Agreement_Sent__c = true;
        update vo;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Vendor Agreement Signed', status, 'Status should advance to "Vendor Agreement Signed" after vendor agreement sent flag is set');

        // --- STEP 12: Vendor Agreements Completed ---
        // Mark VO as signed
        vo.Vendor_Agreement_Signed__c = true;
        update vo;

        // Update Opportunity
        opp.All_Vendors_Agreement_Completed__c = true;
        update opp;
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Closed Won', status, 'Status should advance to "Closed Won" (path logic) after all vendor agreements are completed');

        // --- STEP 13: Final State ---
        opp.StageName = 'Closed Won';
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Closed Won', status, 'Final status returned should be "Closed Won" when Opportunity Stage is "Closed Won"');

        Test.stopTest();
    }
}