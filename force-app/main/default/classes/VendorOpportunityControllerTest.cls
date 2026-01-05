@isTest
public class VendorOpportunityControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('vendtest');

        // 2. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Test Vendor Opp Controller', u.Id);

        // 3. Create Vendor
        TestDataUtility.createVendor('Test Supplier', 'Plumbing', 'supplier@test.com');
    }

    // ==========================================
    // FIELD SET TESTS
    // ==========================================

    @isTest
    static void testGetFieldSetFieldsInvalid() {
        Test.startTest();
        List<VendorOpportunityController.FieldSetMember> fields = 
            VendorOpportunityController.getFieldSetFields('NonExistentObject', 'NonExistentFieldSet');
        Test.stopTest();

        Assert.isNotNull(fields, 'Should return empty list, not null');
        Assert.areEqual(0, fields.size(), 'Should return 0 fields');
    }
    
    @isTest
    static void testGetFieldSetFieldsValidObjectInvalidSet() {
        Test.startTest();
        List<VendorOpportunityController.FieldSetMember> fields = 
            VendorOpportunityController.getFieldSetFields('Vendor_Opportunity__c', 'NonExistentFieldSet');
        Test.stopTest();
        
        Assert.areEqual(0, fields.size(), 'Should return 0 fields for missing field set');
    }

    // ==========================================
    // RECORD MANAGEMENT TESTS
    // ==========================================

    @isTest
    static void testHasExistingRecordsFalse() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Boolean exists = VendorOpportunityController.hasExistingRecords(opp.Id);
        Test.stopTest();

        Assert.areEqual(false, exists, 'Should return false when no records exist');
    }

    @isTest
    static void testHasExistingRecordsTrue() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // FIXED: Changed 'Draft' to 'Active'
        TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');

        Test.startTest();
        Boolean exists = VendorOpportunityController.hasExistingRecords(opp.Id);
        Test.stopTest();

        Assert.areEqual(true, exists, 'Should return true when records exist');
    }

    @isTest
    static void testCreateVendorOpportunities() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // FIXED: Changed 'Draft' to 'Active'
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Vendor__c = vendor.Id,
            Vendor_Opportunity_Status__c = 'Active' 
        );
        List<Vendor_Opportunity__c> records = new List<Vendor_Opportunity__c>{ vo };

        Test.startTest();
        List<Vendor_Opportunity__c> results = VendorOpportunityController.createVendorOpportunities(records, opp.Id);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return inserted record');
        Assert.isNotNull(results[0].Id, 'Id should be generated');
        
        Vendor_Opportunity__c inserted = [SELECT Opportunity__c FROM Vendor_Opportunity__c WHERE Id = :results[0].Id];
        Assert.areEqual(opp.Id, inserted.Opportunity__c, 'Controller should force link to Opportunity');
    }

    @isTest
    static void testGetExistingRecords() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

        // FIXED: Changed 'Draft' to 'Active'
        TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');

        Test.startTest();
        List<String> queryFields = new List<String>{'Vendor_Opportunity_Status__c', 'Vendor__c'};
        List<Vendor_Opportunity__c> results = VendorOpportunityController.getExistingRecords(opp.Id, queryFields);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 record');
        Assert.isNotNull(results[0].Vendor_Opportunity_Status__c, 'Queried field should be present');
    }

    // ==========================================
    // FILE HANDLING TESTS
    // ==========================================

    @isTest
    static void testReparentFiles() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        
        // FIXED: Changed 'Draft' to 'Active'
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');
        
        ContentVersion cv = TestDataUtility.createContentVersion('Test File', 'Content');
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        Map<String, String> fileMap = new Map<String, String>();
        fileMap.put(docId, vo.Id);

        Test.startTest();
        VendorOpportunityController.reparentFiles(fileMap);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink 
            WHERE LinkedEntityId = :vo.Id 
            AND ContentDocumentId = :docId
        ];
        Assert.areEqual(1, links.size(), 'File should be linked to Vendor Opportunity');
    }

    @isTest
    static void testGetAttachedFileNames() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        
        // FIXED: Changed 'Draft' to 'Active'
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');
        
        ContentVersion cv = TestDataUtility.createContentVersion('MySpec', 'Content');
        TestDataUtility.linkFileToRecord(cv.Id, vo.Id);

        Test.startTest();
        Map<Id, String> fileMap = VendorOpportunityController.getAttachedFileNames(new List<Id>{ vo.Id });
        Test.stopTest();

        Assert.isTrue(fileMap.containsKey(vo.Id), 'Map should contain the VO Id');
        String fileName = fileMap.get(vo.Id);
        Assert.isTrue(fileName.contains('MySpec'), 'File name should be returned');
    }
}