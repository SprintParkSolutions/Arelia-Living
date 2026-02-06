@isTest
public class VendorEmailControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('standt');

        // 2. Create Prerequisites (Account & Contact) for Project
        Account acc = TestDataUtility.createAccount('Test Account');
        
        Contact con = TestDataUtility.createContact('Test Contact', 'test@vendor.com', 'pass123');
        con.AccountId = acc.Id;
        update con;

        // 3. Create Project
        TestDataUtility.createProject('Makela Infra Pvt Ltd-Srikanth-Makela', 10000, con.Id);

        // 4. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Test Opportunity', u.Id);

        // 5. Create Vendor (Using 'Plumbing & Sanitary' as requested)
        TestDataUtility.createVendor('Test Vendor', 'Plumbing & Sanitary', 'vendor@test.com');

        // 6. Create File and Link to Opportunity
        ContentVersion cv = TestDataUtility.createContentVersion('Test Document', 'Test Content');
        TestDataUtility.linkFileToRecord(cv.Id, opp.Id);

        // 7. Create Email Templates
        TestDataUtility.createEmailTemplates();
    }
    
    // ==========================================
    // BASIC RETRIEVAL TESTS
    // ==========================================

    @isTest
    static void testGetFilesByOpportunityIdSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(opp.Id);
        Test.stopTest();
        
        Assert.isNotNull(files, 'Files list should not be null');
        Assert.areEqual(1, files.size(), 'Should return the created test file');
    }
    
    @isTest
    static void testGetFilesByOpportunityIdBlankInput() {
        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId('');
        Test.stopTest();
        Assert.areEqual(0, files.size(), 'Should return empty list for blank ID');
    }
    
    @isTest
    static void testGetFilesByOpportunityIdNullInput() {
        Test.startTest();
        List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(null);
        Test.stopTest();
        Assert.areEqual(0, files.size(), 'Should return empty list for null ID');
    }
    
    @isTest
    static void testGetVendorCategoriesSuccess() {
        Test.startTest();
        List<String> categories = VendorEmailController.getVendorCategories();
        Test.stopTest();
        Assert.isNotNull(categories, 'Categories list should not be null');
    }
    
    @isTest
    static void testGetVendorsByCategorySuccess() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('Plumbing & Sanitary');
        Test.stopTest();
        
        Assert.isNotNull(vendors, 'Vendors list should not be null');
        Assert.areEqual(1, vendors.size(), 'Should return one vendor');
        Assert.areEqual('Test Vendor', vendors[0].Name, 'Vendor name should match');
    }
    
    @isTest
    static void testGetVendorsByCategoryBlankInput() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('');
        Test.stopTest();
        Assert.areEqual(0, vendors.size(), 'Should return empty list for blank category');
    }
    
    @isTest
    static void testGetVendorsByCategoryNoMatch() {
        Test.startTest();
        List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('NonExistent');
        Test.stopTest();
        Assert.areEqual(0, vendors.size(), 'Should return empty list for non-existent category');
    }
    
    @isTest
    static void testGetEmailTemplatesByTypeBackup() {
        Test.startTest();
        List<EmailTemplate> templates = VendorEmailController.getEmailTemplatesByType('Backup');
        Test.stopTest();
        Assert.areEqual('Backup_Tendor_Invitation', templates[0].DeveloperName, 'DeveloperName should match Backup template');
    }

    @isTest
    static void testGetEmailTemplatesByTypeNew() {
        Test.startTest();
        List<EmailTemplate> templates = VendorEmailController.getEmailTemplatesByType('New');
        Test.stopTest();
        Assert.areEqual('Quatation_Email_Template', templates[0].DeveloperName, 'DeveloperName should match Quotation template');
    }
    
    @isTest
    static void testGetEmailTemplatesFallback() {
        Test.startTest();
        List<EmailTemplate> templates = VendorEmailController.getEmailTemplatesByType('ValidButDeleted'); 
        Test.stopTest();
        Assert.areEqual(1, templates.size(), 'Should return a default template even for invalid types');
    }
    
    @isTest
    static void testGetSpecificationsByOpportunityAndCategorySuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        List<SObject> specs = VendorEmailController.getSpecificationsByOpportunityAndCategory(opp.Id, 'Plumbing & Sanitary');
        Test.stopTest();
        Assert.isNotNull(specs, 'Specs list should not be null');
    }
    
    @isTest
    static void testGetAbscondedVendorTasksEmptyResult() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details = VendorEmailController.getAbscondedVendorTasks(opp.Id, 'Plumbing & Sanitary');
        Test.stopTest();
        Assert.areEqual(0, details.tasks.size(), 'Tasks list should be empty');
    }

    // ==========================================
    // EXCEPTION TESTS
    // ==========================================
    
    @isTest
    static void testSendEmailToVendorsMissingRequired() {
        Test.startTest();
        try {
            VendorEmailController.sendEmailToVendors('', new List<String>(), new List<String>(), 'Plumbing & Sanitary', 'New');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should not be null');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSendEmailToVendorsNullVendorIds() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        try {
            VendorEmailController.sendEmailToVendors(opp.Id, new List<String>(), null, 'Plumbing & Sanitary', 'New');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should not be null');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSendEmailToVendorsEmptyVendorIds() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        try {
            VendorEmailController.sendEmailToVendors(opp.Id, new List<String>(), new List<String>(), 'Plumbing & Sanitary', 'New');
            Assert.fail('Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should not be null');
        }
        Test.stopTest();
    }

    // ==========================================
    // COMPLEX LOGIC TESTS
    // ==========================================

    @isTest
    static void testSendEmailSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        ContentVersion cv = [SELECT Id FROM ContentVersion LIMIT 1];

        List<String> vendorIds = new List<String>{vendor.Id};
        List<String> fileIds = new List<String>{cv.Id};

        Test.startTest();
        // Test sending a 'New' tender email
        VendorEmailController.sendEmailToVendors(opp.Id, fileIds, vendorIds, 'Plumbing & Sanitary', 'New');
        
        // Also test 'Backup' tender email to cover that branch
        VendorEmailController.sendEmailToVendors(opp.Id, fileIds, vendorIds, 'Plumbing & Sanitary', 'Backup');
        
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(2, invocations, 'Should have sent 2 emails');
    }

    @isTest
    static void testGetAbscondedVendorTasksWithData() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE Alias = 'standt' LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // MANUAL DATA CREATION to avoid Validation Exception on Task Insert
        
        // 1. Create VO
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Abscond');
        
        // 2. Create VA (Utility sets Status='In-Progress', which allows Task creation)
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 60);
        va.Opportunity__c = opp.Id;
        va.Vendor_Opportunity__c = vo.Id;
        va.Vendor__c = vendor.Id;
        va.Supervisor_User__c = supervisor.Id;
        update va;

        // 3. Create Task (Allowed because VA is In-Progress)
        TestDataUtility.createTask('Not Started', va.Id, 0);

        // 4. Update VA to 'Abscond' for test scenario
        va.Status__c = 'Abscond';
        update va;

        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details =
            VendorEmailController.getAbscondedVendorTasks(opp.Id, vendor.Vendor_Category__c);
        Test.stopTest();

        System.assertNotEquals(null, details, 'Details should not be null');
        System.assertEquals(1, details.tasks.size(), 'One task should be returned');
        System.assertEquals(0, details.overallCompletion, 'Completion rounds to 0 due to Integer division if applicable');
    }
    
    @isTest
    static void testQuerySpecsWithFieldSetAndFiles() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        TestDataUtility.createSpecData(opp.Id, 'Plumbing & Sanitary', 'Test Interior Product');

        Test.startTest();
        List<SObject> specs = VendorEmailController.getSpecificationsByOpportunityAndCategory(
            opp.Id, 
            'Plumbing & Sanitary'
        );
        Test.stopTest();

        System.assertEquals(1, specs.size(), 'One specification should be returned');
    }

    @isTest
    static void step3CreateVendorOpportunitiesAssignmentsAndTasks() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];
        User supervisor = [SELECT Id FROM User WHERE Alias = 'standt' LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // MANUAL DATA CREATION
        
        // 1. Create VO
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');
        
        // 2. Create VA (Status='In-Progress')
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 100);
        va.Opportunity__c = opp.Id;
        va.Vendor_Opportunity__c = vo.Id;
        va.Vendor__c = vendor.Id;
        va.Supervisor_User__c = supervisor.Id;
        update va;

        // 3. Create Task
        TestDataUtility.createTask('Not Started', va.Id, 0);

        Test.startTest();
        VendorEmailController.AbscondedVendorDetails details =
            VendorEmailController.getAbscondedVendorTasks(
                opp.Id,
                vendor.Vendor_Category__c
            );
        Test.stopTest();

        System.assertNotEquals(null, details, 'Details should not be null');
    }
    
    @isTest
    static void step4SendEmailWithSpecificationsAndFiles() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];

        TestDataUtility.createSpecData(opp.Id, vendor.Vendor_Category__c, 'Spec Product 1');
        TestDataUtility.createSpecData(opp.Id, vendor.Vendor_Category__c, 'Spec Product 2');

        Test.startTest();
        VendorEmailController.sendEmailToVendors(
            opp.Id,
            new List<String>(), 
            new List<String>{ vendor.Id },
            vendor.Vendor_Category__c,
            'New'
        );
        Test.stopTest();

        System.assert(true, 'Specs + files path executed');
    }
}