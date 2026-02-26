/**
 * @description       : Test class for AreliaPathController
 * @group             : Test
 * @last modified on  : 02-24-2026
 **/
@isTest
public class AreliaPathControllerTest {

    @testSetup
    static void setupData() {
        // We bypass the utility class here to give the user the System Administrator profile.
        // This ensures the Flow 'Project Update Supervisor user to owner' does not crash 
        // with a TRANSFER_REQUIRES_READ error when creating the Project.
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User supervisor = new User(
            Alias = 'suptst', 
            Email = 'suptst@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = sysAdminProfile.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'suptst' + DateTime.now().getTime() + '@testorg.com'
        );
        insert supervisor;

        // Create base opportunity linked to our admin supervisor
        Opportunity opp = TestDataUtility.createOpportunity('Path Controller Test Opp', supervisor.Id);
    }

    @isTest
    static void testGetAllStages() {
        Test.startTest();
        List<Map<String, String>> stages = AreliaPathController.getAllStages();
        Test.stopTest();
        
        System.assertNotEquals(null, stages, 'Stages list should not be null');
        System.assert(stages.size() > 0, 'Stages list should contain items');
    }

    @isTest
    static void testExceptionStages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        
        // Satisfy the custom validation rule before changing stage to 'Resumed'
        opp.All_Vendors_Agreement_Completed__c = true;
        opp.StageName = 'Resumed';
        update opp;
        System.assertEquals('Resumed', AreliaPathController.getPathStatus(opp.Id), 'Should return Resumed exception stage');

        // Note: If Negotiation/Review also has a validation rule, you may need to satisfy it here too.
        opp.StageName = 'Negotiation/Review';
        update opp;
        System.assertEquals('Negotiation/Review', AreliaPathController.getPathStatus(opp.Id), 'Should return Negotiation/Review exception stage');
        
        Test.stopTest();
    }

    @isTest
    static void testInitialStages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        
        // 1. Architect_Name__c is blank
        System.assertEquals('Enter Architect Data', AreliaPathController.getPathStatus(opp.Id), 'Should prompt for Architect Data');

        // 2. Client approval not sent
        opp.Architect_Name__c = 'Test Architect';
        update opp;
        System.assertEquals('Send Architecture Client Approval', AreliaPathController.getPathStatus(opp.Id), 'Should prompt to send architecture client approval');

        // 3. Waiting for Client Architecture Approval (No approved design)
        opp.Architecture_Client_Approval_Sent__c = true;
        update opp;
        System.assertEquals('Client Architecture Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Client Architecture Approval');

        // 4. Waiting for Architecture Manager Approval
        TestDataUtility.createArchitectureDesign(opp.Id, 'file123', 'Approved');
        System.assertEquals('Architecture Manager Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Manager Architecture Approval');

        // 5. Manager Approved -> Moves to Proforma
        opp.Architecture_Manager_Approval__c = true;
        update opp;
        System.assertEquals('Upload Proforma Invoice', AreliaPathController.getPathStatus(opp.Id), 'Should progress to Upload Proforma Invoice');
        
        Test.stopTest();
    }

    @isTest
    static void testProformaStages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Architect_Name__c = 'Test Architect';
        opp.Architecture_Client_Approval_Sent__c = true;
        opp.Architecture_Manager_Approval__c = true;
        update opp;
        TestDataUtility.createArchitectureDesign(opp.Id, 'file123', 'Approved');
        
        Test.startTest();

        // 1. No Proforma Invoice
        System.assertEquals('Upload Proforma Invoice', AreliaPathController.getPathStatus(opp.Id), 'Should prompt to upload Proforma');

        // 2. Proforma Invoice created but Changes Requested
        Proforma_Invoice__c pi = TestDataUtility.createProformaInvoice(opp.Id);
        pi.Status__c = 'Changes Requested';
        update pi;
        System.assertEquals('Upload Proforma Invoice', AreliaPathController.getPathStatus(opp.Id), 'Should prompt to upload Proforma if changes requested');

        // 3. Proforma Sent
        pi.Status__c = 'Sent';
        update pi;
        System.assertEquals('Proforma Client Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Proforma Client Approval');

        // 4. Proforma Approved by Client but not Manager
        pi.Status__c = 'Approved';
        update pi;
        System.assertEquals('Proforma Manager Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Proforma Manager Approval');

        // 5. Proforma Manager Approved -> Moves to Budget (Skipping Catalogue as link is false)
        pi.Manager_Approval__c = true;
        update pi;
        System.assertEquals('Budget Review Client Approval', AreliaPathController.getPathStatus(opp.Id), 'Should progress to Budget Review');
        
        Test.stopTest();
    }

    @isTest
    static void testCatalogueStages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Architect_Name__c = 'Test Architect';
        opp.Architecture_Client_Approval_Sent__c = true;
        opp.Architecture_Manager_Approval__c = true;
        opp.Catalogue_Link_Sent__c = true; // Enables Catalogue logic
        update opp;
        
        TestDataUtility.createArchitectureDesign(opp.Id, 'file123', 'Approved');
        Proforma_Invoice__c pi = TestDataUtility.createProformaInvoice(opp.Id);
        pi.Status__c = 'Approved';
        pi.Manager_Approval__c = true;
        update pi;
        
        Test.startTest();

        // 1. Catalogue Link Sent, waiting for Quotation
        System.assertEquals('Catalogue Received', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Catalogue (Quotation)');

        // 2. Quotation received but no Manager Approval
        Quotation__c q = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        System.assertEquals('Catalogue Manager Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Catalogue Manager Approval');

        // 3. Manager Approved -> Moves to Budget
        q.Manager_Approval__c = true;
        update q;
        System.assertEquals('Budget Review Client Approval', AreliaPathController.getPathStatus(opp.Id), 'Should progress to Budget Review');

        Test.stopTest();
    }

    @isTest
    static void testBudgetAndPaymentStages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Architect_Name__c = 'Test Architect';
        opp.Architecture_Client_Approval_Sent__c = true;
        opp.Architecture_Manager_Approval__c = true;
        update opp;
        
        TestDataUtility.createArchitectureDesign(opp.Id, 'file123', 'Approved');
        Proforma_Invoice__c pi = TestDataUtility.createProformaInvoice(opp.Id);
        pi.Status__c = 'Approved';
        pi.Manager_Approval__c = true;
        update pi;
        
        Test.startTest();

        // 1. Waiting for Budget Client Approval
        System.assertEquals('Budget Review Client Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Budget Client Approval');

        // 2. Budget Client Approved -> Waiting for Manager
        opp.Budget_Review_Status__c = 'Client Approved';
        update opp;
        System.assertEquals('Budget Review Manager Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Budget Manager Approval');

        // 3. Budget Manager Approved -> Waiting for Payment Manager
        opp.Budget_Review_Status__c = 'Manager Approved';
        update opp;
        System.assertEquals('Payment Terms Manager Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Payment Terms Manager Approval');

        // 4. Payment Manager Approved -> Waiting for Payment Client
        opp.Payment_Terms_Status__c = 'Manager Approved';
        update opp;
        System.assertEquals('Payment Terms Client Approval', AreliaPathController.getPathStatus(opp.Id), 'Should wait for Payment Terms Client Approval');

        // 5. Payment Client Approved -> Moves to Agreement
        opp.Payment_Terms_Status__c = 'Client Approved';
        update opp;
        System.assertEquals('Client Agreement Sent', AreliaPathController.getPathStatus(opp.Id), 'Should progress to Client Agreement Sent');

        Test.stopTest();
    }

    @isTest
    static void testVendorAndClosingStages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Architect_Name__c = 'Test Architect';
        opp.Architecture_Client_Approval_Sent__c = true;
        opp.Architecture_Manager_Approval__c = true;
        opp.Budget_Review_Status__c = 'Manager Approved';
        opp.Payment_Terms_Status__c = 'Client Approved';
        update opp;
        
        TestDataUtility.createArchitectureDesign(opp.Id, 'file123', 'Approved');
        Proforma_Invoice__c pi = TestDataUtility.createProformaInvoice(opp.Id);
        pi.Status__c = 'Approved';
        pi.Manager_Approval__c = true;
        update pi;
        
        Test.startTest();

        // 1. Client Agreement Status
        System.assertEquals('Client Agreement Sent', AreliaPathController.getPathStatus(opp.Id), 'Should prompt to send agreement');
        
        opp.Client_Agreement_Sent__c = true;
        update opp;
        System.assertEquals('Client Agreement Signed', AreliaPathController.getPathStatus(opp.Id), 'Should wait for signed client agreement');

        // 2. Vendor Tender Invites
        opp.Client_Agreement_Signed__c = true;
        update opp;
        System.assertEquals('Tender Invites', AreliaPathController.getPathStatus(opp.Id), 'Should prompt for Tender Invites');

        // 3. Vendor Agreement Signed
        Vendor__c v = TestDataUtility.createVendor('WoodWorks Inc.', 'Carpentry & Woodwork', 'vendor@wood.com');
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, v.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true;
        update vo;
        System.assertEquals('Vendor Agreement Signed', AreliaPathController.getPathStatus(opp.Id), 'Should wait for all vendors to be signed');

        // FIX: Satisfy the org's validation rule by checking the signed checkbox
        vo.Vendor_Agreement_Signed__c = true; 
        update vo;

        // 4. Closed Won check if not already in Closed Won
        opp.All_Vendors_Agreement_Completed__c = true;
        update opp;
        System.assertEquals('Closed Won', AreliaPathController.getPathStatus(opp.Id), 'Should return Closed Won to prompt stage update');

        // 5. Final validation when StageName is already Closed Won
        opp.StageName = 'Closed Won';
        update opp;
        System.assertEquals('Closed Won', AreliaPathController.getPathStatus(opp.Id), 'Final state should be Closed Won');

        Test.stopTest();
    }
}