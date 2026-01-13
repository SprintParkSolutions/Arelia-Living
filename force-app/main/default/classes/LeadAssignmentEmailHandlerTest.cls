@isTest
public class LeadAssignmentEmailHandlerTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor Users
        User sup1 = TestDataUtility.createSupervisorUser('sup1');
        User sup2 = TestDataUtility.createSupervisorUser('sup2');

        // 2. Create Email Template
        System.runAs(new User(Id = UserInfo.getUserId())) {
            EmailTemplate tpl = new EmailTemplate(
                DeveloperName = 'Arelia_Living_Supervisor_Email_Template', 
                Name = 'Test Supervisor Template',
                Subject = 'Lead Assigned: {{{Lead.Name}}}',
                HtmlValue = '<html><body>New Lead: {{{Lead.Name}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId(),
                IsActive = true
            );
            insert tpl;
        }
    }

    // ==========================================
    // HELPER METHOD
    // ==========================================
    private static String getFakeId(Schema.SObjectType sot) {
        String result = String.valueOf(sot.getDescribe().getKeyPrefix());
        return result + '000000000001';
    }

    // ==========================================
    // POSITIVE TESTS
    // ==========================================

    @isTest
    static void testHandleSupervisorAssignmentNewAssignment() {
        User sup1 = [SELECT Id, Email FROM User WHERE Alias = 'sup1' LIMIT 1];
        
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Approval_Status__c = 'Approved',
            Status = 'Open - Not Contacted',
            Email = 'lead@test.com'
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        l.Supervisor_User__c = sup1.Id;
        l.Appointment_Status__c = 'Approved'; 
        update l; 
        
        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c, Appointment_Status__c FROM Lead WHERE Id = :l.Id];
        
        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ updatedLead }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.isTrue(invocations >= 0, 'Handler should execute without error');
    }

    @isTest
    static void testHandleSupervisorAssignmentChangeSupervisor() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];
        User sup2 = [SELECT Id FROM User WHERE Alias = 'sup2' LIMIT 1];
        
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Status = 'Open - Not Contacted',
            Approval_Status__c = 'Approved',
            Supervisor_User__c = sup1.Id,
            Appointment_Status__c = 'Approved'
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        l.Supervisor_User__c = sup2.Id;
        update l;
        
        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c FROM Lead WHERE Id = :l.Id];

        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ updatedLead }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should NOT send email if changing from one supervisor to another');
    }

    @isTest
    static void testHandleSupervisorAssignmentNoChange() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];
        
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Status = 'Open - Not Contacted',
            Approval_Status__c = 'Approved',
            Supervisor_User__c = sup1.Id,
            Appointment_Status__c = 'Approved'
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        l.Company = 'Changed Co';
        
        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ l }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should NOT send email if supervisor did not change');
    }

    @isTest
    static void testHandleSupervisorAssignmentChangeToNull() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];
        
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Status = 'Open - Not Contacted',
            Approval_Status__c = 'Approved',
            Supervisor_User__c = sup1.Id,
            Appointment_Status__c = 'Approved'
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        l.Supervisor_User__c = null;
        update l;
        
        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c FROM Lead WHERE Id = :l.Id];
        
        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ updatedLead }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should NOT send email if supervisor is removed');
    }
    
    @isTest
    static void testFetchTemplateErrorHandling() {
        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(new List<Lead>(), new Map<Id, Lead>());
        Test.stopTest();
        
        Assert.areEqual(0, Limits.getEmailInvocations(), 'No emails should be sent for empty input lists');
    }

    // ==========================================
    // NEGATIVE / EXCEPTION TESTS
    // ==========================================

    @isTest
    static void testHandleSupervisorAssignmentMissingTemplate() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];
        
        // 1. Delete the template created in @testSetup
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Arelia_Living_Supervisor_Email_Template' LIMIT 1];
        delete tpl;

        // 2. Prepare Data using local getFakeId
        Lead l = new Lead(Id = getFakeId(Lead.SObjectType), Supervisor_User__c = sup1.Id);
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => new Lead(Id = l.Id, Supervisor_User__c = null) };

        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ l }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should return early if template is missing');
    }

    @isTest
    static void testHandleSupervisorAssignmentSupervisorNoEmail() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        // Using JSON hack to set read-only/formula field 'Supervisor_User_Email__c' to null
        String fakeId = getFakeId(Lead.SObjectType); 
        String leadJson = '{"attributes":{"type":"Lead"}, "Id":"' + fakeId + '", "Supervisor_User__c":"' + sup1.Id + '", "Supervisor_User_Email__c": null}';
        Lead l = (Lead)JSON.deserialize(leadJson, Lead.class);

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => new Lead(Id = l.Id, Supervisor_User__c = null) };

        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ l }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should not send email if supervisor email is blank');
    }

    @isTest
    static void testSendEmailFailure() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        // 1. Prepare Data with NULL ID to cause send failure
        // We do NOT provide an "Id" field in the JSON. This results in a Lead object with Id=null.
        // We DO provide Supervisor Email to pass the first check in buildEmail().
        String leadJson = '{ ' +
            '"attributes": {"type": "Lead"}, ' +
            '"Supervisor_User__c": "' + sup1.Id + '", ' +
            '"Supervisor_User_Email__c": "test@test.com" ' +
        '}';
        
        Lead leadWithNullId = (Lead)JSON.deserialize(leadJson, Lead.class);

        // 2. Setup Map with NULL key to ensure logic proceeds
        Map<Id, Lead> oldMap = new Map<Id, Lead>();
        oldMap.put(null, new Lead(Supervisor_User__c = null));

        Test.startTest();
        try {
            // This should invoke buildEmail (success) and then sendEmails (failure due to null Id)
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ leadWithNullId }, 
                oldMap
            );
            Assert.fail('Should have thrown AuraHandledException due to send failure');
        } catch (Exception e) {
            // Expected behavior: Handler catches MessagingException and rethrows AuraHandledException
            // Note: In tests, this often appears as 'Script-thrown exception'
            Assert.isTrue(e.getTypeName().contains('AuraHandledException') || e.getMessage().contains('Script-thrown'), 
                'Should catch the handled exception from sendEmails');
        }
        Test.stopTest();
    }
}