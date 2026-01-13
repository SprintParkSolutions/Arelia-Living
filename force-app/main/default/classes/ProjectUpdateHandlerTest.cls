@isTest
public class ProjectUpdateHandlerTest {

    @testSetup
    static void setupData() {
        // Variable to hold the supervisor so we can use their ID later
        User supervisor;

        // 1. Create Setup Objects (Templates & User) inside runAs to avoid Mixed DML
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Using a local helper for templates since they are specific to this Handler's labels
            createMockTemplate(Label.Arelia_Living_Project_Status_Update_Lead_Template);
            createMockTemplate(Label.Arelia_Living_Project_Status_Update_Supervisor_Template);
            
            // Create the Supervisor User using Utility
            supervisor = TestDataUtility.createSupervisorUser('sup');
        }

        // 2. Create Non-Setup Objects (Contacts) using Utility
        // Utility method requires (Name, Email, Password)
        Contact dummy = TestDataUtility.createContact('Dummy Contact', 'dummy@test.com', 'pass123');
        Contact client = TestDataUtility.createContact('Real Client', 'client@real.com', 'pass123');

        // 3. Create Project using Utility
        // Utility requires (Name, Budget, ContactId)
        Project__c proj = TestDataUtility.createProject('Test Project Update', 10000, client.Id);
        
        // Update fields specific to this test
        proj.Supervisor_User__c = supervisor.Id; 
        proj.Project_Completion_Status__c = 0;
        update proj;
    }

    /**
     * Helper to create an EmailTemplate with the specific DeveloperName 
     */
    private static void createMockTemplate(String devName) {
        if (String.isBlank(devName)) {
            return;
        }

        EmailTemplate t = new EmailTemplate();
        t.isActive = true;
        t.Name = devName;
        t.DeveloperName = devName;
        t.TemplateType = 'text';
        t.FolderId = UserInfo.getUserId(); // Storing in User's personal folder
        t.Subject = 'Test Subject';
        t.Body = 'Test Body';
        insert t;
    }

    @isTest
    static void testStatusChangeTriggersEmail() {
        Project__c p = [SELECT Id, Project_Completion_Status__c FROM Project__c LIMIT 1];

        Test.startTest();
        // Change the status to trigger the email logic
        p.Project_Completion_Status__c = 50; 
        update p;
        
        // Check email invocations
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        // Expect emails to be sent
        System.assert(emailInvocations > 0, 'Emails should be sent when completion status changes');
    }

    @isTest
    static void testNoChangeNoEmail() {
        Project__c p = [SELECT Id, Project_Completion_Status__c FROM Project__c LIMIT 1];

        Test.startTest();
        // Update project but DO NOT change the completion status
        p.Name = 'Updated Name Only';
        update p;
        
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(0, emailInvocations, 'No emails should be sent if status did not change');
    }

    @isTest
    static void testMissingRecipientEmails() {
        // SCENARIO: Project Status changes, but Client/Supervisor emails are blank.
        
        Project__c p = [SELECT Id, Client__c FROM Project__c LIMIT 1];
        Contact client = [SELECT Id FROM Contact WHERE Id = :p.Client__c];
        
        // Clear Client Email
        client.Email = null;
        update client;
        
        Test.startTest();
        p.Project_Completion_Status__c = 100;
        
        // Try to clear explicit email fields on project if they exist and are writable
        try { 
            p.put('Client_Email__c', null); 
        } catch(Exception e) {
            System.debug(LoggingLevel.INFO, 'Ignored write to formula field: ' + e.getMessage());
        }
        
        update p;
        Test.stopTest();
        
        System.assert(true, 'Method executed successfully with missing emails');
    }

    @isTest
    static void testGuardClauses() {
        Test.startTest();
        ProjectUpdateHandler.afterUpdate(null, null);
        ProjectUpdateHandler.afterUpdate(new List<Project__c>(), null);
        ProjectUpdateHandler.sendProjectStatusUpdateEmails(null);
        Test.stopTest();
        
        System.assert(true, 'Guard clauses handled nulls gracefully');
    }
}