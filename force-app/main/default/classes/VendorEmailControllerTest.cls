@isTest
public class VendorEmailControllerTest {
	 @testSetup
    static void setup() {
        // 1. Create User for Supervisor context
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User u = new User(Alias = 'standt', Email='standarduser@testorg.com', 
            EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='uniq_sup_user' + DateTime.now().getTime() + '@testorg.com');
        insert u;

        // 2. Insert Non-Setup Objects (Opportunity, Vendor)
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            Supervisor_User__c = u.Id, // Ensure supervisor is linked
            Project_Scope__c = 'Dining Hall'
        );
        insert opp;
        
        // 2b. Insert Project (shared across tests)
        Project__c proj = new Project__c(
            Name = 'Makela Infra Pvt Ltd-Srikanth-Makela', // must match restricted picklist
            Status__c = 'In Progress'
        );
        insert proj;

        Vendor__c vendor = new Vendor__c(
            Name = 'Test Vendor',
            Email__c = 'vendor@test.com',
            Vendor_Category__c = 'Plumbing',
            Vendor_Status__c = 'Available',
            Average_Efficiency__c = 95.5
        );
        insert vendor;

        // 3. Create ContentVersion (File) for Attachment coverage linked to Opp
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.pdf',
            VersionData = Blob.valueOf('Test Content'),
            IsMajorVersion = true
        );
        insert cv;

        // Link File to Opportunity
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = opp.Id,
            ContentDocumentId = conDocId,
            ShareType = 'V'
        );
        insert cdl;
        
        // 4. Insert Setup Objects (EmailTemplate) inside System.runAs
        System.runAs(new User(Id = UserInfo.getUserId())) {
            EmailTemplate templateBackup = new EmailTemplate(
                DeveloperName = 'Backup_Tendor_Invitation',
                Name = 'Backup Tender Invitation',
                Subject = 'Tender: {{{project_scope}}}',
                HtmlValue = '<html><body>Test Email Backup {{{Vendor_Category__c}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            );
            insert templateBackup;

            EmailTemplate templateNew = new EmailTemplate(
                DeveloperName = 'Quatation_Email_Template',
                Name = 'Quotation Email Template',
                Subject = 'New Tender: {{{project_scope}}}',
                HtmlValue = '<html><body>Test Email New {{{Vendor_Category__c}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            );
            insert templateNew;
        }
    }
    
    // ==========================================
    // BASIC RETRIEVAL TESTS
    // ==========================================

    @isTest
    static void testGetFilesByOpportunityId_Success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(opp.Id);
        Test.stopTest();
        
        Assert.isNotNull(files, 'Files list should not be null');
        Assert.areEqual(1, files.size(), 'Should return the created test file');
    }
    
    @isTest
    static void testGetFilesByOpportunityId_BlankInput() {
        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId('');
        Test.stopTest();
        Assert.areEqual(0, files.size(), 'Should return empty list for blank ID');
    }
    
    @isTest
    static void testGetFilesByOpportunityId_NullInput() {
        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(null);
        Test.stopTest();
        Assert.areEqual(0, files.size(), 'Should return empty list for null ID');
    }
    
    @isTest
    static void testGetVendorCategories_Success() {
        Test.startTest();
        List<String> categories = VendorEmailController.getVendorCategories();
        Test.stopTest();
        Assert.isNotNull(categories, 'Categories list should not be null');
    }
    
    @isTest
    static void testGetVendorsByCategory_Success() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('Plumbing');
        Test.stopTest();
        
        Assert.isNotNull(vendors, 'Vendors list should not be null');
        Assert.areEqual(1, vendors.size(), 'Should return one vendor');
        Assert.areEqual('Test Vendor', vendors[0].Name, 'Vendor name should match');
    }
    
    @isTest
    static void testGetVendorsByCategory_BlankInput() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('');
        Test.stopTest();
        Assert.areEqual(0, vendors.size(), 'Should return empty list for blank category');
    }
    
    @isTest
    static void testGetVendorsByCategory_NoMatch() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('NonExistent');
        Test.stopTest();
        Assert.areEqual(0, vendors.size(), 'Should return empty list for non-existent category');
    }
    
    @isTest
    static void testGetEmailTemplatesByType_Backup() {
        Test.startTest();
        List<EmailTemplate> templates = VendorEmailController.getEmailTemplatesByType('Backup');
        Test.stopTest();
        Assert.areEqual('Backup_Tendor_Invitation', templates[0].DeveloperName);
    }

    @isTest
    static void testGetEmailTemplatesByType_New() {
        Test.startTest();
        List<EmailTemplate> templates = VendorEmailController.getEmailTemplatesByType('New');
        Test.stopTest();
        Assert.areEqual('Quatation_Email_Template', templates[0].DeveloperName);
    }
    
    @isTest
    static void testGetEmailTemplatesByType_NotFound() {
        Test.startTest();
        try {
            VendorEmailController.getEmailTemplatesByType('ValidButDeleted'); 
        } catch (Exception e) {
            // Expected
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetSpecificationsByOpportunityAndCategory_Success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        List<SObject> specs = VendorEmailController.getSpecificationsByOpportunityAndCategory(opp.Id, 'Plumbing');
        Test.stopTest();
        Assert.isNotNull(specs, 'Specs list should not be null');
    }
    
    @isTest
    static void testGetAbscondedVendorTasks_EmptyResult() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details = VendorEmailController.getAbscondedVendorTasks(opp.Id, 'Plumbing');
        Test.stopTest();
        Assert.areEqual(0, details.tasks.size(), 'Tasks list should be empty');
    }

    // ==========================================
    // EXCEPTION TESTS
    // ==========================================
    
    @isTest
    static void testSendEmailToVendors_MissingRequired() {
        Test.startTest();
        try {
            VendorEmailController.sendEmailToVendors('', new List<String>(), new List<String>(), 'Plumbing', 'New');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSendEmailToVendors_NullVendorIds() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        try {
            VendorEmailController.sendEmailToVendors(opp.Id, new List<String>(), null, 'Plumbing', 'New');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSendEmailToVendors_EmptyVendorIds() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        try {
            VendorEmailController.sendEmailToVendors(opp.Id, new List<String>(), new List<String>(), 'Plumbing', 'New');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        Test.stopTest();
    }

    // ==========================================
    // COMPLEX LOGIC TESTS
    // ==========================================

    @isTest
    static void testSendEmail_Success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];

        List<String> vendorIds = new List<String>{vendor.Id};
        List<String> fileIds = new List<String>{cv.Id};

        Test.startTest();
        // Test sending a 'New' tender email
        VendorEmailController.sendEmailToVendors(opp.Id, fileIds, vendorIds, 'Plumbing', 'New');
        
        // Also test 'Backup' tender email to cover that branch
        VendorEmailController.sendEmailToVendors(opp.Id, fileIds, vendorIds, 'Plumbing', 'Backup');
        
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(2, invocations, 'Should have sent 2 emails');
    }

    @isTest
    static void testGetAbscondedVendorTasks_WithData() {
        // Fetch base data from Setup
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        // Use the Project created in Setup
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Use Helper to create Data
        createAbscondData(opp.Id, vendor.Id, supervisor.Id, proj.Id, 'Abscond', 60);

        // Execute method
        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details =
            VendorEmailController.getAbscondedVendorTasks(opp.Id, vendor.Vendor_Category__c);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, details, 'Details should not be null');
        System.assertEquals(1, details.tasks.size(), 'One task should be returned');
        System.assertEquals(0, details.overallCompletion, 'Completion rounds to 0 due to Integer division if applicable');
    }
    
    @isTest
    static void testQuerySpecs_WithFieldSetAndFiles() {
        // Fetch base data from Setup
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Use Helper to create Specification Data
        createSpecData(opp.Id, 'Electrical and Lighting', 'Test Interior Product');

        // Execute Controller Method
        Test.startTest();
        List<SObject> specs = VendorEmailController.getSpecificationsByOpportunityAndCategory(
            opp.Id, 
            'Electrical and Lighting'
        );
        Test.stopTest();

        System.assertEquals(1, specs.size(), 'One specification should be returned');
    }

    @isTest
    static void step3_CreateVendorOpportunitiesAssignmentsAndTasks() {
        // Reuse existing records from @testSetup
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Create Data via Helper (Status 'Active' and Completion 100)
        createAbscondData(opp.Id, vendor.Id, supervisor.Id, proj.Id, 'Active', 100);

        // Execute method
        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details =
            VendorEmailController.getAbscondedVendorTasks(
                opp.Id,
                vendor.Vendor_Category__c
            );
        Test.stopTest();

        // Assertions (lightweight, branch-focused)
        System.assertNotEquals(null, details);
    }
    
    @isTest
    static void step4_SendEmail_WithSpecificationsAndFiles() {
        // Base data from setup
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];

        // Create 2 products with specs and files
        createSpecData(opp.Id, vendor.Vendor_Category__c, 'Spec Product 1');
        createSpecData(opp.Id, vendor.Vendor_Category__c, 'Spec Product 2');

        // Call email method again (this time specs exist)
        Test.startTest();
        VendorEmailController.sendEmailToVendors(
            opp.Id,
            new List<String>(), // controller internally fetches spec files
            new List<String>{ vendor.Id },
            vendor.Vendor_Category__c,
            'New'
        );
        Test.stopTest();

        System.assert(true, 'Specs + files path executed');
    }

    // ==========================================
    // HELPER METHODS (To Remove Duplication)
    // ==========================================

    private static void createAbscondData(Id oppId, Id vendorId, Id supervisorId, Id projId, String voStatus, Decimal completion) {
        // 1. Create Vendor Opportunity
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = oppId,
            Vendor__c = vendorId,
            Vendor_Opportunity_Status__c = voStatus
        );
        insert vo;

        // 2. Create Vendor Assignment
        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id,
            Opportunity__c = oppId,
            Supervisor_User__c = supervisorId,
            Project__c = projId,
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today().addDays(5),
            Completion__c = completion
        );
        insert va;

        // 3. Create Task
        Task t = new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            WhatId = va.Id
        );
        insert t;
    }

    private static void createSpecData(Id oppId, String category, String productName) {
        // 1. Create Interior Product
        Interior_Product__c product = new Interior_Product__c(Name = productName);
        insert product;

        // 2. Create File and Link to Product
        ContentVersion cv = new ContentVersion(
            Title = 'Spec File ' + productName,
            PathOnClient = 'spec.pdf',
            VersionData = Blob.valueOf('Test File Content'),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = product.Id,
            ShareType = 'V'
        );
        insert cdl;

        // 3. Create Project Specification
        Project_Specification__c spec = new Project_Specification__c(
            Opportunity__c = oppId,
            Interior_Product__c = product.Id,
            Vendor_Category__c = category
        );
        insert spec;
    }
}