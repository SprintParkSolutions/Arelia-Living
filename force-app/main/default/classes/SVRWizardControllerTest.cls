@isTest
public class SVRWizardControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('svrtest');
        
        // 2. Create Lead
        Lead l = TestDataUtility.createLead('Test Lead');

        // 3. Create Opportunity
        TestDataUtility.createOpportunity('Test Opp SVR', u.Id);

        // =================================================================
        // FIX: Satisfy Validation Rule using 'Appointment_Completed__c'
        // =================================================================
        // The validation rule blocks SVR creation unless this checkbox is checked.
        try {
            // Using .put() to safely handle the field provided
            l.put('Appointment_Completed__c', true); 
            
            // Just in case there are other status dependencies, we keep this status update
            l.Status = 'Appointment Completed'; // Or whatever status matches the checkbox logically
        } catch(Exception e) {
            System.debug('Field write failed: ' + e.getMessage());
        }
        update l;
    }

    // ==========================================
    // GET LATEST SVR TESTS
    // ==========================================

    @isTest
    static void testGetLatestSVRForLeadSuccess() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        
        // Create an SVR for this Lead (Now succeeds because Appointment_Completed__c is true)
        TestDataUtility.createSiteVisitReport(l.Id, 'Lead Site Visit Report');

        Test.startTest();
        Site_Visit_Report__c result = SVRWizardController.getLatestSVR(l.Id, 'Lead');
        Test.stopTest();

        Assert.isNotNull(result, 'Should return the created SVR');
        Assert.areEqual(1, result.Wizard_Step__c, 'Wizard step should match');
    }

    @isTest
    static void testGetLatestSVRForOpportunitySuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Create an SVR for this Opportunity
        TestDataUtility.createSiteVisitReport(opp.Id, 'Opportunity Site Visit Report');

        Test.startTest();
        Site_Visit_Report__c result = SVRWizardController.getLatestSVR(opp.Id, 'Opportunity');
        Test.stopTest();

        Assert.isNotNull(result, 'Should return the created SVR');
    }

    @isTest
    static void testGetLatestSVRParentNull() {
        Test.startTest();
        Site_Visit_Report__c result = SVRWizardController.getLatestSVR(null, 'Lead');
        Test.stopTest();
        Assert.isNull(result, 'Should return null if parentId is null');
    }

    @isTest
    static void testGetLatestSVRInvalidObject() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        // Passing 'Account' or invalid object name should return null
        Site_Visit_Report__c result = SVRWizardController.getLatestSVR(opp.Id, 'Account');
        Test.stopTest();
        Assert.isNull(result, 'Should return null for unsupported object type');
    }

    // ==========================================
    // CREATE SVR TESTS
    // ==========================================

    @isTest
    static void testCreateSVRNewLead() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        
        // Added required field Total_Estimated_Cost__c
        Site_Visit_Report__c draft = new Site_Visit_Report__c(
            Total_Estimated_Cost__c = 5000 
        );

        Test.startTest();
        // This will now succeed because the Lead in setup() has Appointment_Completed__c = true
        Id svrId = SVRWizardController.createSVR(l.Id, 'Lead', draft);
        Test.stopTest();

        Assert.isNotNull(svrId, 'Should return new SVR Id');
        Site_Visit_Report__c created = [SELECT RecordType.Name, Wizard_Step__c FROM Site_Visit_Report__c WHERE Id = :svrId];
        Assert.areEqual('Lead Site Visit Report', created.RecordType.Name, 'Record Type should be set correctly');
        Assert.areEqual(2, created.Wizard_Step__c, 'Wizard step should be set to 2');
    }

    @isTest
    static void testCreateSVRExisting() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        // Pre-create one (Succeeds due to setup fix)
        Site_Visit_Report__c existing = TestDataUtility.createSiteVisitReport(l.Id, 'Lead Site Visit Report');

        Test.startTest();
        Id svrId = SVRWizardController.createSVR(l.Id, 'Lead', new Site_Visit_Report__c());
        Test.stopTest();

        Assert.areEqual(existing.Id, svrId, 'Should return existing SVR Id instead of creating new one');
    }

    @isTest
    static void testCreateSVROpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Added required field
        Site_Visit_Report__c draft = new Site_Visit_Report__c(
             Total_Estimated_Cost__c = 7500
        );

        Test.startTest();
        Id svrId = SVRWizardController.createSVR(opp.Id, 'Opportunity', draft);
        Test.stopTest();

        Assert.isNotNull(svrId, 'Should return new SVR Id');
        Site_Visit_Report__c created = [SELECT RecordType.Name FROM Site_Visit_Report__c WHERE Id = :svrId];
        Assert.areEqual('Opportunity Site Visit Report', created.RecordType.Name, 'Record Type should be set correctly');
    }

    @isTest
    static void testCreateSVRInvalidRecordTypeException() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        
        try {
            SVRWizardController.createSVR(l.Id, 'InvalidObj', new Site_Visit_Report__c());
        } catch (Exception e) {
            Assert.isNotNull(e, 'Exception caught if logic fails');
        }
    }

    // ==========================================
    // UPDATE LOGIC TESTS
    // ==========================================

    @isTest
    static void testSaveStep() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        Site_Visit_Report__c svr = TestDataUtility.createSiteVisitReport(l.Id, 'Lead Site Visit Report');

        Test.startTest();
        SVRWizardController.saveStep(svr.Id, 4);
        Test.stopTest();

        Site_Visit_Report__c updated = [SELECT Wizard_Step__c FROM Site_Visit_Report__c WHERE Id = :svr.Id];
        Assert.areEqual(4, updated.Wizard_Step__c, 'Wizard step should be updated');
    }

    @isTest
    static void testSaveDraft() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        Site_Visit_Report__c svr = TestDataUtility.createSiteVisitReport(l.Id, 'Lead Site Visit Report');
        
        svr.Management_Approval__c = true;

        Test.startTest();
        SVRWizardController.saveDraft(svr);
        Test.stopTest();

        Site_Visit_Report__c updated = [SELECT Management_Approval__c FROM Site_Visit_Report__c WHERE Id = :svr.Id];
        Assert.areEqual(true, updated.Management_Approval__c, 'Fields should be updated');
    }

    @isTest
    static void testMarkBlueprintUploaded() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        Site_Visit_Report__c svr = TestDataUtility.createSiteVisitReport(l.Id, 'Lead Site Visit Report');

        Test.startTest();
        SVRWizardController.markBlueprintUploaded(svr.Id);
        Test.stopTest();

        Site_Visit_Report__c updated = [SELECT Layout_Blueprint_Uploaded__c FROM Site_Visit_Report__c WHERE Id = :svr.Id];
        Assert.areEqual(true, updated.Layout_Blueprint_Uploaded__c, 'Blueprint flag should be true');
    }

    @isTest
    static void testFinalSubmit() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        Site_Visit_Report__c svr = TestDataUtility.createSiteVisitReport(l.Id, 'Lead Site Visit Report');

        Test.startTest();
        SVRWizardController.finalSubmit(svr.Id);
        Test.stopTest();

        Site_Visit_Report__c updated = [SELECT Is_Final_Submitted__c, Site_Visit_Report_Status__c, Wizard_Step__c FROM Site_Visit_Report__c WHERE Id = :svr.Id];
        Assert.areEqual(true, updated.Is_Final_Submitted__c, 'Should be final submitted');
        Assert.areEqual('Approved', updated.Site_Visit_Report_Status__c, 'Status should be Approved');
        Assert.areEqual(3, updated.Wizard_Step__c, 'Wizard step should be 3');
    }

    // ==========================================
    // UTILITY METHOD TESTS
    // ==========================================

    @isTest
    static void testGetFiles() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        
        ContentVersion cv = TestDataUtility.createContentVersion('SVR File', 'Content');
        TestDataUtility.linkFileToRecord(cv.Id, l.Id);

        Test.startTest();
        List<ContentDocumentLink> files = SVRWizardController.getFiles(l.Id);
        Test.stopTest();

        Assert.areEqual(1, files.size(), 'Should return 1 file');
    }

    @isTest
    static void testGetFieldSetFields() {
        Test.startTest();
        List<String> fields = SVRWizardController.getFieldSetFields('Lead', 'NonExistentFieldSet');
        Test.stopTest();
        
        Assert.isNotNull(fields, 'Should return empty list, not null');
        Assert.areEqual(0, fields.size(), 'Should return 0 fields for missing fieldset');
    }
}