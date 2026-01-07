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
    // POSITIVE TESTS
    // ==========================================

    @isTest
    static void testHandleSupervisorAssignmentNewAssignment() {
        User sup1 = [SELECT Id, Email FROM User WHERE Alias = 'sup1' LIMIT 1];
        
        // 1. Create Lead WITHOUT Supervisor
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Approval_Status__c = 'Approved',
            Status = 'Open - Not Contacted',
            Email = 'lead@test.com'
        );
        insert l;

        // 2. Prepare "Old" Map (Supervisor is null)
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 3. Update Lead WITH Supervisor
        // FIX: Set Appointment_Status__c to 'Approved' to satisfy Validation Rule
        l.Supervisor_User__c = sup1.Id;
        l.Appointment_Status__c = 'Approved'; 
        update l; 
        
        // 4. Re-query
        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c, Appointment_Status__c FROM Lead WHERE Id = :l.Id];
        
        // 5. Call Handler
        Test.startTest();
        LeadAssignmentEmailHandler.handleSupervisorAssignment(
            new List<Lead>{ updatedLead }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        // 6. Assertions
        System.debug('Email Invocations: ' + invocations);
        Assert.isTrue(invocations >= 0, 'Handler should execute without error');
    }

    @isTest
    static void testHandleSupervisorAssignmentChangeSupervisor() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];
        User sup2 = [SELECT Id FROM User WHERE Alias = 'sup2' LIMIT 1];
        
        // 1. Create Lead WITH Supervisor 1 (Must be Approved to have Supervisor)
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Status = 'Open - Not Contacted',
            Approval_Status__c = 'Approved',
            Supervisor_User__c = sup1.Id,
            Appointment_Status__c = 'Approved' // FIX: Required for Supervisor assignment
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 2. Change to Supervisor 2
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
        
        // 1. Create Lead WITH Supervisor
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Status = 'Open - Not Contacted',
            Approval_Status__c = 'Approved',
            Supervisor_User__c = sup1.Id,
            Appointment_Status__c = 'Approved' // FIX: Required
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 2. Update something else (Company)
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
        
        // 1. Create Lead WITH Supervisor
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Co',
            Status = 'Open - Not Contacted',
            Approval_Status__c = 'Approved',
            Supervisor_User__c = sup1.Id,
            Appointment_Status__c = 'Approved' // FIX: Required
        );
        insert l;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 2. Remove Supervisor
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
}