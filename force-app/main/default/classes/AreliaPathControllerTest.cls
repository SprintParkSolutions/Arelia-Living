@IsTest
@SuppressWarnings('PMD.ApexAssertionsShouldIncludeMessage')
public class AreliaPathControllerTest {

    @TestSetup
    static void setup() {
        // 1. Create Supervisor User as SYSTEM ADMINISTRATOR
        // We do this manually instead of using the Utility to ensure they have permissions
        // to own the Project object, preventing the "TRANSFER_REQUIRES_READ" flow error.
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User u = new User(
            Alias = 'pathUser', 
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
        // We wrap this in System.runAs to avoid MIXED_DML_OPERATION errors 
        // (mixing User insertion with Opportunity insertion).
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = TestDataUtility.createOpportunity('Path Test Opp', u.Id);
            
            // Ensure all flags start as false/null to test the very first stage
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
        Assert.areEqual(17, stages.size(), 'Should return all 17 defined stages');
        
        // Verify a specific new stage exists
        Boolean foundNewStage = false;
        for (Map<String, String> stage : stages) {
            if (stage.get('value') == 'Send Architecture Client Approval') {
                foundNewStage = true;
                break;
            }
        }
        Assert.isTrue(foundNewStage, 'Should contain the new Architecture stage');
    }

    // ==========================================
    // 2. Test Priority Overrides (Resumed/Negotiation)
    // ==========================================
    @IsTest
    static void testPathStatusOverrides() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Test Resumed
        opp.StageName = 'Resumed';
        update opp;
        String status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Resumed', status, 'StageName "Resumed" should override other logic');

        // Test Negotiation
        opp.StageName = 'Negotiation/Review';
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Negotiation/Review', status, 'StageName "Negotiation/Review" should override other logic');
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
        Assert.areEqual('Send Architecture Client Approval', status, 'Initial status incorrect');

        // --- STEP 2: Architecture Sent ---
        opp.Architecture_Client_Approval_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Architecture Approval', status, 'Status after sending architecture incorrect');

        // --- STEP 3: Architecture Approved ---
        Architecture_Design__c design = new Architecture_Design__c(
            Opportunity__c = opp.Id,
            Status__c = 'Approved'
        );
        insert design;
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Architecture Manager Approval', status, 'Status after architecture approval incorrect');

        // --- STEP 4: Manager Approval ---
        opp.Architecture_Manager_Approval__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Catalogue Link Sent', status, 'Status after manager approval incorrect');

        // --- STEP 5: Catalogue Link Sent ---
        opp.Catalogue_Link_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Catalogue Received', status, 'Status after catalogue link sent incorrect');

        // --- STEP 6: Payment Terms Created ---
        TestDataUtility.createPaymentTerm(opp.Id, '50% Advance', 50.00);
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Create Payment Terms', status, 'Status after payment terms created incorrect');

        // --- STEP 7: Quotation Created (Unapproved) ---
        Quotation__c quote = TestDataUtility.createQuotation(opp.Id, 'Test Quote'); 
        quote.Manager_Approval__c = false; 
        update quote;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Specifications & Payment Terms Manager approval', status, 'Status after quotation creation incorrect');

        // --- STEP 8: Quotation Approved ---
        quote.Manager_Approval__c = true;
        update quote;
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Agreement Sent', status, 'Status after quotation approval incorrect');

        // --- STEP 9: Agreement Sent ---
        opp.Client_Agreement_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Agreement Signed', status, 'Status after agreement sent incorrect');

        // --- STEP 10: Agreement Signed ---
        opp.Client_Agreement_Signed__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Tender Invites', status, 'Status after agreement signed incorrect');

        // --- STEP 11: Vendor Agreement Sent ---
        Vendor__c v = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'v@test.com');
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id,
            Vendor__c = v.Id,
            Vendor_Agreement_Sent__c = true,
            Vendor_Opportunity_Status__c = 'Active'
        );
        insert vo;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Vendor Agreement Signed', status, 'Status after vendor agreement sent incorrect');

        // --- STEP 12: Vendor Agreements Completed ---
        // MUST mark the VO as signed first to pass the validation rule on the Opportunity
        vo.Vendor_Agreement_Signed__c = true;
        update vo;

        // Now update the Opportunity
        opp.All_Vendors_Agreement_Completed__c = true;
        update opp;
        
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Closed Won', status, 'Status after all vendors completed incorrect');

        // --- STEP 13: Final State ---
        opp.StageName = 'Closed Won';
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Closed Won', status, 'Final status incorrect');

        Test.stopTest();
    }
}