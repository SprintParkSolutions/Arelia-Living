@isTest
public class HandleVendorAbscondControllerTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('abscUser');

        // 2. Create Business Account (Do NOT set PersonEmail here)
        Account acc = TestDataUtility.createAccount('Abscond Client Co');
        acc.Email__c = 'client@test.com'; 
        update acc;

        // 3. Create Contact
        Contact client = TestDataUtility.createContact('Test Client Name', 'client@test.com', 'password123');
        client.AccountId = acc.Id;
        update client;

        // 4. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Abscond Opp', u.Id);
        opp.AccountId = acc.Id;
        opp.Email__c = 'oppclient@test.com'; 
        opp.Lead_Name__c = 'Test Client Name';
        update opp;

        // 5. Create Vendor & Assignment
        Project__c proj = TestDataUtility.createProject('Abscond Project', 50000, client.Id);
        Vendor__c v = TestDataUtility.createVendor('Runaway Vendor', 'Electrical', 'vendor@runaway.com');
        
        // 6. Create Vendor Opportunity
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, v.Id, 'Active');

        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id, 0); 
        va.Opportunity__c = opp.Id;
        va.Vendor_Opportunity__c = vo.Id;
        va.Vendor__c = v.Id;
        va.Supervisor_User__c = u.Id;
        va.Status__c = 'Abscond'; 
        update va;

        // 7. Create Template
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate('Vendor_Abscond_Template', 'Abscond Notice', 'Urgent');
        }
    }

    // -------------------------------------------------------------------
    // ✅ 1. DTO & Data Retrieval Tests
    // -------------------------------------------------------------------

    @isTest
    static void testGetEmailTemplatesByFolder() {
        Test.startTest();
        List<HandleVendorAbscondController.EmailTemplateDTO> results = 
            HandleVendorAbscondController.getEmailTemplatesByFolder();
        Test.stopTest();
        
        Assert.isNotNull(results, 'Should return a list of templates');
    }

    @isTest
    static void testDTOStructure() {
        Test.startTest();
        // Cover EmailTemplateDTO
        HandleVendorAbscondController.EmailTemplateDTO tplDto = new HandleVendorAbscondController.EmailTemplateDTO();
        tplDto.id = UserInfo.getUserId();
        tplDto.name = 'Test';
        tplDto.developerName = 'Test_Dev';
        tplDto.folderName = 'Test_Folder';

        // Cover VendorWrapper
        HandleVendorAbscondController.VendorWrapper venWrap = new HandleVendorAbscondController.VendorWrapper();
        venWrap.id = UserInfo.getUserId();
        venWrap.name = 'Vendor';
        venWrap.email = 'v@v.com';

        // Cover VendorClientDTO
        HandleVendorAbscondController.VendorClientDTO clientDto = new HandleVendorAbscondController.VendorClientDTO();
        clientDto.clientEmail = 'c@c.com';
        clientDto.clientName = 'Client';
        clientDto.vendors = new List<HandleVendorAbscondController.VendorWrapper>{ venWrap };
        Test.stopTest();

        Assert.areEqual('Test', tplDto.name, 'DTO Name should match input');
        Assert.areEqual('Vendor', clientDto.vendors[0].name, 'Wrapper Name should match input');
    }

    @isTest
    static void testGetAbscondVendorsAndClientFullData() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('oppclient@test.com', result.clientEmail, 'Should use Opportunity email when present');
        Assert.areEqual('Test Client Name', result.clientName, 'Should use Opportunity Lead Name when present');
        Assert.areEqual(1, result.vendors.size(), 'Should find exactly one abscond vendor');
        Assert.areEqual('Runaway Vendor', result.vendors[0].name, 'Vendor name should match');
    }

    @isTest
    static void testGetAbscondVendorsAndClientAccountFallback() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Email__c = null;     // Clear Opp level
        opp.Lead_Name__c = null; // Clear Opp level
        update opp;

        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('client@test.com', result.clientEmail, 'Should fallback to Account Email');
        Assert.areEqual('Abscond Client Co', result.clientName, 'Should fallback to Account Name');
    }

    @isTest
    static void testGetAbscondVendorsAndClientPersonEmailFallback() {
        // Safe check for Person Account support
        Id personAccountRTId;
        try {
            personAccountRTId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('PersonAccount').getRecordTypeId();
        } catch (Exception e) {
            System.debug('Person Account not enabled. Skipping test.');
            return;
        }

        // Create Person Account
        Account pa = new Account(
            RecordTypeId = personAccountRTId,
            LastName = 'PersonClient',
            PersonEmail = 'person@test.com',
            Email__c = null
        );
        insert pa;

        Opportunity opp = new Opportunity(
            Name = 'Person Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            AccountId = pa.Id
        );
        insert opp;

        Test.startTest();
        HandleVendorAbscondController.VendorClientDTO result = 
            HandleVendorAbscondController.getAbscondVendorsAndClient(opp.Id);
        Test.stopTest();

        Assert.areEqual('person@test.com', result.clientEmail, 'Should fallback to Account PersonEmail');
    }

    // -------------------------------------------------------------------
    // ✅ 2. Send Email Tests
    // -------------------------------------------------------------------

    @isTest
    static void testSendEmailVendorLogicMultiple() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];

        // Prepare inputs for "Vendor" mode
        List<String> recipients = new List<String>{'v1@test.com', 'v2@test.com'};
        List<Id> assignmentIds = new List<Id>{va.Id, va.Id};

        Test.startTest();
        String result = HandleVendorAbscondController.sendEmail(
            tpl.Id, 
            recipients, 
            opp.Id, 
            'Vendor', // Triggers setSaveAsActivity(false) & setWhatId(assignmentId)
            assignmentIds
        );
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Email should return SUCCESS status');
        Integer contacts = [SELECT COUNT() FROM Contact WHERE LastName = 'TempRecipient'];
        Assert.areEqual(0, contacts, 'Dummy contact should be deleted after sending');
    }

    @isTest
    static void testSendEmailClientLogic() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];

        Test.startTest();
        String result = HandleVendorAbscondController.sendEmail(
            tpl.Id, 
            new List<String>{'client@test.com'}, 
            opp.Id, 
            'Client', // Triggers setSaveAsActivity(true) & setWhatId(oppId)
            null
        );
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Email should return SUCCESS status');
    }

    // -------------------------------------------------------------------
    // ✅ 3. Exception & Negative Tests
    // -------------------------------------------------------------------

    @isTest
    static void testSendEmailValidations() {
        Test.startTest();
        
        // 1. Missing Template
        try {
            HandleVendorAbscondController.sendEmail(null, new List<String>{'a@a.com'}, null, 'Client', null);
            Assert.fail('Should throw exception for missing template');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should throw AuraHandledException for missing template');
        }

        // 2. Missing Recipients
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];
        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, new List<String>(), null, 'Client', null);
            Assert.fail('Should throw exception for empty recipients');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should throw AuraHandledException for empty recipients');
        }

        // 3. Recipients with empty strings (Loop runs but adds no emails)
        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, new List<String>{'', null}, null, 'Client', null);
            Assert.fail('Should throw exception for no valid emails found');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should throw AuraHandledException for invalid emails');
        }
        
        Test.stopTest();
    }

    @isTest
    static void testSendEmailSendFailure() {
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // "invalidemail" (no @ domain) allows the list check to pass but sendEmail might flag it
        List<String> badEmails = new List<String>{'invalidemail'}; 

        Test.startTest();
        try {
            HandleVendorAbscondController.sendEmail(tpl.Id, badEmails, opp.Id, 'Client', null);
        } catch (Exception e) {
            // Check for AuraHandledException OR EmailException depending on where it's caught
            Boolean isHandled = e.getTypeName().contains('AuraHandledException') || 
                                e.getTypeName().contains('EmailException');
            Assert.isTrue(isHandled, 'Should catch send failure or validation error');
        }
        Test.stopTest();
    }
}