@isTest
public class VendorAssignmentControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User (Supervisor)
        User u = TestDataUtility.createSupervisorUser('vasup');
        u.Phone = '555-123-4567'; // Populate Phone to avoid nulls in template
        update u;

        // 2. Create Account
        Account acc = TestDataUtility.createAccount('Vendor Account');

        // 3. Create Contact
        Contact con = TestDataUtility.createContact('Vendor Contact', 'vendor@test.com', 'password123');
        con.AccountId = acc.Id;
        update con;

        // 4. Create Vendor (Custom Object)
        // Ensure Email__c is populated as controller relies on it
        Vendor__c vendorObj = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'vendor@test.com');

        // 5. Create Project
        Project__c proj = TestDataUtility.createProject('Test Project VA', 10000, con.Id);

        // 6. Create Vendor Assignment linked to the Vendor (Custom Object)
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 50);
        va.Vendor__c = vendorObj.Id; // Correct Link to Vendor__c Object
        va.Supervisor_User__c = u.Id;
        va.Vendor_Work_Start_Date__c = Date.today();
        va.Vendor_Work_End_Date__c = Date.today().addDays(5);
        // Note: Vendor_Category__c is a formula field, so we don't write to it. 
        // It pulls from vendorObj.Vendor_Category__c which we set in step 4.
        update va;

        // 7. Create Email Template
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String devName = Label.Arelia_Living_Vendor_Project_Assignment;
            if (String.isBlank(devName)) {
                devName = 'Arelia_Living_Vendor_Project_Assignment_TEST';
            }

            // Check if template exists
            List<EmailTemplate> existing = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName LIMIT 1];
            if (existing.isEmpty()) {
                EmailTemplate t = new EmailTemplate();
                t.DeveloperName = devName;
                t.Name = 'Test Vendor Assignment';
                t.Subject = 'Assignment for {{{Vendor_Assignment__c.Project__c}}}';
                // Important: Provide HTML value to prevent NPE in controller's replace methods
                t.HtmlValue = '<html><body>' +
                              'Project: {{{Vendor_Assignment__c.Project__c}}}<br/>' +
                              'Vendor: {{{Vendor_Assignment__c.Vendor__c}}}<br/>' +
                              'Start: {{{Vendor_Assignment__c.Vendor_Work_Start_Date__c}}}<br/>' +
                              'End: {{{Vendor_Assignment__c.Vendor_Work_End_Date__c}}}<br/>' +
                              'Sup Name: {{{Vendor_Assignment__c.Supervisor_User__c}}}<br/>' +
                              'Sup Email: {{{Vendor_Assignment__c.Supervisor_Email}}}<br/>' +
                              'Sup Phone: {{{Vendor_Assignment__c.Supervisor_Phone}}}<br/>' +
                              'Category: {{{Vendor_Assignment__c.Vendor_Category__c}}}' +
                              '</body></html>';
                t.TemplateType = 'custom';
                t.FolderId = UserInfo.getUserId();
                t.IsActive = true;
                insert t;
            }
        }
    }

    @isTest
    static void testGetVendorTasksAsAdmin() {
        Test.startTest();
        // As Admin (no ContactId), this should return an empty list without error
        List<Vendor_Assignment__c> results = VendorAssignmentController.getVendorTasks();
        Test.stopTest();
        Assert.isNotNull(results, 'Should return a list (empty for admin)');
    }

    @isTest
    static void testSendVendorAssignmentEmailSuccess() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        List<Vendor_Assignment__c> input = new List<Vendor_Assignment__c>{ va };

        Test.startTest();
        Integer startEmails = Limits.getEmailInvocations();
        
        VendorAssignmentController.sendVendorAssignmentEmail(input);
        
        Integer endEmails = Limits.getEmailInvocations();
        Test.stopTest();

        // Ensure email was sent (assuming template exists)
        String devName = Label.Arelia_Living_Vendor_Project_Assignment;
        if(String.isNotBlank(devName)) {
             Assert.isTrue((endEmails - startEmails) > 0, 'Email should be sent when template exists');
        }
    }

    @isTest
    static void testSendVendorAssignmentEmailGuardClauses() {
        Test.startTest();
        VendorAssignmentController.sendVendorAssignmentEmail(null);
        VendorAssignmentController.sendVendorAssignmentEmail(new List<Vendor_Assignment__c>());
        Test.stopTest();
        Assert.isTrue(true, 'Method should return gracefully');
    }

    @isTest
    static void testSendVendorAssignmentEmailMissingVendorEmail() {
        Vendor_Assignment__c va = [SELECT Id, Vendor__c FROM Vendor_Assignment__c LIMIT 1];
        
        // Fetch linked Vendor (Custom Object) and clear Email
        Vendor__c v = [SELECT Id FROM Vendor__c WHERE Id = :va.Vendor__c];
        v.put('Email__c', null); 
        update v;
        
        // Update Assignment to refresh relationship
        update va;

        Test.startTest();
        Integer startEmails = Limits.getEmailInvocations();
        VendorAssignmentController.sendVendorAssignmentEmail(new List<Vendor_Assignment__c>{ va });
        Integer endEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(startEmails, endEmails, 'Should NOT send email if vendor email is missing');
    }

    @isTest
    static void testSendVendorAssignmentEmailMissingTemplate() {
        // Find and delete the template to simulate missing config
        String devName = Label.Arelia_Living_Vendor_Project_Assignment;
        if (String.isNotBlank(devName)) {
            List<EmailTemplate> tpls = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName];
            if (!tpls.isEmpty()) {
                delete tpls;
            }
        }

        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        Test.startTest();
        try {
            VendorAssignmentController.sendVendorAssignmentEmail(new List<Vendor_Assignment__c>{ va });
            // The controller throws AuraHandledException if template is missing
            Assert.fail('Should throw AuraHandledException due to missing template');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception expected when template is missing');
        }
        Test.stopTest();
    }
}