@isTest
public class HandleVendorAbscondControllerTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor using Utility
        User u = TestDataUtility.createSupervisorUser('abscUser');

        // 2. Create Account (Client) using Utility
        Account acc = TestDataUtility.createAccount('Abscond Client Co');
        acc.Email__c = 'client@test.com'; // Custom field not in utility, updated here
        update acc;

        // 3. Create Contact (required for Project/Opp in some contexts, good practice)
        Contact client = TestDataUtility.createContact('Test Client Name', 'client@test.com', 'password123');
        client.AccountId = acc.Id;
        update client;

        // 4. Create Opportunity using Utility
        Opportunity opp = TestDataUtility.createOpportunity('Abscond Opp', u.Id);
        
        // Update fields specific to this controller's logic
        opp.AccountId = acc.Id;
        opp.Email__c = 'oppclient@test.com'; 
        opp.Lead_Name__c = 'Test Client Name';
        update opp;

        // 5. Create Vendor using Utility
        Vendor__c v = TestDataUtility.createVendor('Runaway Vendor', 'Electrical & Networking', 'vendor@runaway.com');

        // 6. Create Vendor Opportunity using Utility
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, v.Id, 'Active');

        // 7. Create Project using Utility (requires Budget and Contact)
        Project__c proj = TestDataUtility.createProject('Abscond Project', 50000, client.Id);
        proj.Status__c = 'In Progress'; 
        update proj;

        // 8. Create Vendor Assignment using Utility
        // Utility sets Status to 'In-Progress'. We update it to 'Abscond'.
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 0); 
        
        va.Opportunity__c = opp.Id;
        va.Vendor_Opportunity__c = vo.Id;
        va.Vendor__c = v.Id; // Ensure vendor link is set
        va.Supervisor_User__c = u.Id;
        va.Status__c = 'Abscond'; // Key filter for the controller
        update va;
    }

    // ==========================================
    // EMAIL TEMPLATE TESTS
    // ==========================================

    @isTest
    static void testGetEmailTemplatesByFolder() {
        Test.startTest();
        List<HandleVendorAbscondController.EmailTemplateDTO> templates = 
            HandleVendorAbscondController.getEmailTemplatesByFolder();
        Test.stopTest();

        Assert.isNotNull(templates, 'Should return a list (empty or populated)');
    }

    // ==========================================
    // ABSCOND VENDOR DATA TESTS
    // ==========================================

    @isTest
    static void testGetAbscondVendorsAndClient() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'DTO should not be null');
        Assert.areEqual('oppclient@test.com', result.clientEmail, 'Should prioritize Opportunity email');
        Assert.areEqual('Test Client Name', result.clientName, 'Should map Client Name');

        Assert.isNotNull(result.vendors, 'Vendors list should not be null');
        Assert.areEqual(1, result.vendors.size(), 'Should find 1 abscond vendor');
        
        HandleVendorAbscondController.VendorWrapper vendor = result.vendors[0];
        Assert.areEqual('Runaway Vendor', vendor.name, 'Vendor name should match');
        Assert.areEqual('vendor@runaway.com', vendor.email, 'Vendor email should match');
    }

    @isTest
    static void testGetAbscondVendorsAccountFallback() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        // Clear Opp level fields to test Account fallback
        opp.Email__c = null;
        opp.Lead_Name__c = null;
        update opp;

        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('client@test.com', result.clientEmail, 'Should fallback to Account email');
        Assert.areEqual('Abscond Client Co', result.clientName, 'Should fallback to Account Name');
    }

    // ==========================================
    // SEND EMAIL TESTS
    // ==========================================

    @isTest
    static void testSendEmailVendorContext() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        
        // Wrap Setup Object creation in System.runAs
        EmailTemplate tpl;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Using Utility to create template if possible, or manual if specific logic needed
            tpl = TestDataUtility.createSpecificEmailTemplate(
                'Test_Abscond_Template',
                'Test Abscond',
                'Warning'
            );
            // Utility creates it Active by default, which is correct
        }

        List<String> recipients = new List<String>{'vendor@test.com'};
        List<Id> assignmentIds = new List<Id>{va.Id};

        Test.startTest();
        String result = HandleVendorAbscondController.sendEmail(
            tpl.Id, 
            recipients, 
            opp.Id, 
            'Vendor', 
            assignmentIds
        );
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Email should send successfully');
        
        Integer contacts = [SELECT COUNT() FROM Contact WHERE LastName = 'TempRecipient'];
        Assert.areEqual(0, contacts, 'Dummy contact should be deleted');
    }

    @isTest
    static void testSendEmailClientContext() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Wrap Setup Object creation in System.runAs
        EmailTemplate tpl;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tpl = TestDataUtility.createSpecificEmailTemplate(
                'Test_Client_Template',
                'Test Client',
                'Update'
            );
        }

        Test.startTest();
        String result = HandleVendorAbscondController.sendEmail(
            tpl.Id, 
            new List<String>{'client@test.com'}, 
            opp.Id, 
            'Client', 
            null 
        );
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Email should send successfully');
    }

    @isTest
    static void testSendEmailValidationMissingTemplate() {
        Test.startTest();
        try {
            HandleVendorAbscondController.sendEmail(null, new List<String>{'a@a.com'}, null, 'Client', null);
            Assert.fail('Should throw exception for missing template');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testSendEmailValidationMissingRecipients() {
        // Wrap Setup Object creation in System.runAs
        EmailTemplate tpl;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tpl = TestDataUtility.createSpecificEmailTemplate(
                'Test_Val_Template',
                'Test Val',
                'S'
            );
        }

        Test.startTest();
        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, new List<String>(), null, 'Client', null);
            Assert.fail('Should throw exception for empty recipients');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception expected');
        }
        Test.stopTest();
    }
}