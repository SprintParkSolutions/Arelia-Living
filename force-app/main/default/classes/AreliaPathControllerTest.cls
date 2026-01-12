@isTest
public class AreliaPathControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('pathtest');

        // 2. Create Opportunity
        TestDataUtility.createOpportunity('Path Test Opp', u.Id);
        
        // 3. Create Vendor
        // Ensure 'Plumbing' is a valid Active Picklist Value
        TestDataUtility.createVendor('Path Vendor', 'Painting & Wall Finishing', 'path@vendor.com');
    }

    @isTest
    static void testGetAllStages() {
        Test.startTest();
        List<Map<String, String>> stages = AreliaPathController.getAllStages();
        Test.stopTest();

        Assert.isNotNull(stages, 'Stages list should not be null');
        Assert.areEqual(13, stages.size(), 'Should return 13 defined stages');
        Assert.areEqual('Catalogue Sent', stages[0].get('value'), 'First stage should be Catalogue Sent');
    }

    // ==========================================
    // PROGRESSION TESTS
    // ==========================================

    @isTest
    static void testPathStatusStep1CatalogueSent() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Catalogue Sent', status, 'Status should be Catalogue Sent initially');
    }

    @isTest
    static void testPathStatusStep2CreatePaymentTerms() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        TestDataUtility.createQuotation(opp.Id, 'Test Quote');

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Create Payment Terms', status, 'Status should advance to Create Payment Terms');
    }

    @isTest
    static void testPathStatusStep3ManagerApproval() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        q.Manager_Approval__c = false;
        update q;

        TestDataUtility.createPaymentTerm(opp.Id, 'Advance', 10.0);

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Specifications & Payment Terms Manager approval', status, 'Status should wait for Manager Approval');
    }

    @isTest
    static void testPathStatusStep4ClientAgreementSent() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        q.Manager_Approval__c = true;
        update q;

        TestDataUtility.createPaymentTerm(opp.Id, 'Advance', 10.0);
        
        opp.Client_Agreement_Sent__c = false;
        update opp;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Client Agreement Sent', status, 'Status should be Client Agreement Sent');
    }

    @isTest
    static void testPathStatusStep5ClientAgreementSigned() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        q.Manager_Approval__c = true;
        update q;
        TestDataUtility.createPaymentTerm(opp.Id, 'Advance', 10.0);

        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = false;
        update opp;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Client Agreement Signed', status, 'Status should wait for Client Signature');
    }

    @isTest
    static void testPathStatusStep6TenderInvites() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        q.Manager_Approval__c = true;
        update q;
        TestDataUtility.createPaymentTerm(opp.Id, 'Advance', 10.0);

        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        update opp;

        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = false; 
        update vo;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Tender Invites', status, 'Status should be Tender Invites');
    }

    @isTest
    static void testPathStatusStep7VendorAgreementSigned() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        q.Manager_Approval__c = true;
        update q;
        TestDataUtility.createPaymentTerm(opp.Id, 'Advance', 10.0);

        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        // Ensure this field is false so we stop at this stage
        opp.All_Vendors_Agreement_Completed__c = false;
        update opp;

        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true; 
        update vo;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Vendor Agreement Signed', status, 'Status should be Vendor Agreement Signed');
    }

    @isTest
    static void testPathStatusStep8ClosedWon() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // 1. Setup Prerequisites
        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        q.Manager_Approval__c = true;
        update q;
        TestDataUtility.createPaymentTerm(opp.Id, 'Advance', 10.0);

        // 2. Update Opp Status
        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        opp.StageName = 'Proposal'; 
        update opp;

        // 3. Setup Vendor Opportunity to satisfy 'All_Vendors_Agreement_Completed__c'
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');
        
        // Try multiple ways to satisfy the "Signed" completion logic
        try {
            vo.put('Vendor_Agreement_Signed__c', true);
        } catch(Exception e) {
            // Fallback
             try {
                vo.put('Vendor_Opportunity_Status__c', 'Agreement Signed');
             } catch(Exception ex) {
                System.debug('Could not auto-set completion field: ' + ex.getMessage());
             }
        }
        
        // FIX: Ensure 'Sent' is TRUE immediately before update, overwriting any side effects from status change
        vo.Vendor_Agreement_Sent__c = true; 
        update vo;

        // Manually satisfy final condition if formula/triggers don't run in test context
        opp.All_Vendors_Agreement_Completed__c = true;
        update opp;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Closed Won', status, 'Status should finally be Closed Won');
    }

    // ==========================================
    // NEW TESTS FOR NEW STAGES
    // ==========================================

    @isTest
    static void testPathStatusNegotiation() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        opp.StageName = 'Negotiation/Review';
        update opp;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Negotiation/Review', status, 'Status should reflect Negotiation/Review priority');
    }

    @isTest
    static void testPathStatusResumed() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        opp.StageName = 'Resumed';
        update opp;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Resumed', status, 'Status should reflect Resumed priority');
    }
}