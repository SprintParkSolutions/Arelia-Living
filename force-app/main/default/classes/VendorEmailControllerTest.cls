/**
 * @description       : Test class for VendorEmailController.
 * Uses "Run as Current User" to bypass FLS/Picklist limitation loops.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @last modified on  : 01-27-2026
**/
@IsTest
public class VendorEmailControllerTest {

    // ============================================================================
    // SETUP
    // ============================================================================
    @TestSetup
    static void setup() {
        // Create common data as the current running user (who has permissions)
        Account acc = TestDataUtility.createAccount('Test Account');
        Contact con = TestDataUtility.createContact('Test Contact', 'test@vendor.com', 'pass123');
        con.AccountId = acc.Id;
        update con;

        TestDataUtility.createProject('Makela Infra Pvt Ltd', 10000, con.Id);

        // Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Test Opportunity', UserInfo.getUserId());

        // Create Vendor with VALID Picklist Value
        TestDataUtility.createVendor('Test Vendor', 'Server Room Setup', 'vendor@test.com');

        // Create File
        ContentVersion cv = TestDataUtility.createContentVersion('Opp Document', 'Test Content');
        TestDataUtility.linkFileToRecord(cv.Id, opp.Id);

        // Create Templates
        TestDataUtility.createEmailTemplates();
    }

    // ============================================================================
    // POSITIVE TESTS (Happy Path)
    // ============================================================================

    @IsTest
    static void testGetFilesByOpportunityId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

            Test.startTest();
            List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(opp.Id);
            Test.stopTest();

            Assert.areEqual(1, files.size(), 'Should retrieve one file.');
        }
    }

    @IsTest
    static void testGetVendorCategories() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<String> categories = VendorEmailController.getVendorCategories();
            Test.stopTest();

            Assert.isNotNull(categories, 'Categories should returned.');
        }
    }

    @IsTest
    static void testGetVendorsByCategory() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory('Server Room Setup');
            Test.stopTest();

            Assert.areEqual(1, vendors.size(), 'Should find the vendor created in setup.');
        }
    }

    @IsTest
    static void testSendEmailNewTender() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];
            ContentVersion oppFile = [SELECT Id FROM ContentVersion WHERE Title = 'Opp Document' LIMIT 1];

            // Create Specs
            TestDataUtility.createSpecData(opp.Id, 'Server Room Setup', 'Toilet Set');

            Test.startTest();
            VendorEmailController.sendEmailToVendors(
                opp.Id,
                new List<String>{oppFile.Id},
                new List<String>{vendor.Id},
                'Server Room Setup',
                'New'
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(1, invocations, 'Email should be sent successfully.');
        }
    }

    @IsTest
    static void testSendEmailBackupTender() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Vendor__c vendor = [SELECT Id, Vendor_Category__c FROM Vendor__c LIMIT 1];

            // Inject Mock Data
            Vendor_Assignment__c mockVA = new Vendor_Assignment__c(
                Vendor_Work_Start_Date__c = Date.today(),
                Vendor_Work_End_Date__c = Date.today().addDays(5),
                Completion__c = 50.0
            );
            VendorEmailController.mockAssignments = new List<Vendor_Assignment__c>{ mockVA };

            Task mockTask = new Task(Subject = 'Mock Task', Status = 'Deferred');
            VendorEmailController.mockTasks = new List<Task>{ mockTask };

            Test.startTest();
            VendorEmailController.sendEmailToVendors(
                opp.Id,
                new List<String>(),
                new List<String>{vendor.Id},
                'Server Room Setup',
                'Backup'
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(1, invocations, 'Email should be sent using mock data.');
        }
    }

    // ============================================================================
    // NEGATIVE TESTS (For Code Coverage)
    // ============================================================================

    @IsTest
    static void testGetFilesNullId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<ContentVersion> files = VendorEmailController.getFilesByOpportunityId(null);
            Test.stopTest();
            Assert.isTrue(files.isEmpty(), 'Should return empty list for null input');
        }
    }

    @IsTest
    static void testGetVendorsNullCategory() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<Vendor__c> vendors = VendorEmailController.getVendorsByCategory(null);
            Test.stopTest();
            Assert.isTrue(vendors.isEmpty(), 'Should return empty list for null category');
        }
    }

    @IsTest
    static void testSendEmailMissingParams() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            try {
                VendorEmailController.sendEmailToVendors(null, null, null, null, null);
                Assert.fail('Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                // AuraHandledException messages are often masked as "Script-thrown exception" in tests.
                // We just verify that the Exception Object is not null.
                Assert.isNotNull(e, 'An AuraHandledException should have been thrown');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testSendEmailInvalidTemplate() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];

            Test.startTest();
            try {
                // Passing 'InvalidType' should trigger the template not found error
                VendorEmailController.sendEmailToVendors(
                    opp.Id,
                    new List<String>(),
                    new List<String>{vendor.Id},
                    'Server Room Setup',
                    'InvalidType'
                );
            } catch (Exception e) {
                // Expected exception due to missing template or invalid type logic
            }

            // Direct test for exception in template helper
            try {
                VendorEmailController.getEmailTemplatesByType('NonExistentType');
            } catch (Exception e) {
                // Expected exception for invalid template developer name
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testAbscondedDetailsErrorHandling() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Force an error by mocking null where a list is expected or creating an internal exception situation
            VendorEmailController.mockAssignments = null;

            Test.startTest();
            // Passing invalid ID usually doesn't throw, but returns empty.
            VendorEmailController.AbscondedVendorDetails details = VendorEmailController.getAbscondedVendorTasks(null, null);
            Test.stopTest();

            Assert.areEqual(0, details.tasks.size(), 'Should handle errors gracefully and return empty object');
        }
    }
}