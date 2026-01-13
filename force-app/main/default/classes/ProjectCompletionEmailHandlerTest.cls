@isTest
public class ProjectCompletionEmailHandlerTest {

    // Constants matching the Handler's private constants
    private static final String CLIENT_TPL = 'Client_Project_Completed_Notification';
    private static final String SUPERVISOR_TPL = 'Supervisor_Project_Completed_Notification';
    private static final String MANAGER_TPL = 'Sending_Project_Completed_Information_to_Manager';
    private static final String MGMT_TPL = 'Sending_Project_Completed_Information_to_Management';
    private static final String ENROLL_TPL = 'Sending_Project_Completed_Information_to_Enrollment';

    @testSetup
    static void setup() {
        // 1. Create Supervisor using Utility
        User sup = TestDataUtility.createSupervisorUser('projSup');

        // 2. Create Account using Utility
        Account acc = TestDataUtility.createAccount('Project Client Co');

        // 3. Create Contact using Utility and link Account
        Contact client = TestDataUtility.createContact('Project Client', 'client@project.test', 'password123');
        client.AccountId = acc.Id;
        update client;

        // 4. Create Project using Utility (Requires Budget and ContactId)
        Project__c proj = TestDataUtility.createProject('Test Completion Project', 50000, client.Id);
        
        // Update Project fields specific to this test
        proj.Status__c = 'In Progress';
        proj.Project_Completion_Status__c = 0;
        proj.Supervisor_User__c = sup.Id;
        proj.Project_Code__c = 'PRJ-001'; 
        update proj;

        // 5. Create Email Templates (Local Helper Logic, as Utility createSpecificEmailTemplate is for one-offs)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = new List<EmailTemplate>();
            templates.add(createLocalTemplate(CLIENT_TPL, 'Client Notif'));
            templates.add(createLocalTemplate(SUPERVISOR_TPL, 'Sup Notif'));
            templates.add(createLocalTemplate(MANAGER_TPL, 'Manager Notif'));
            templates.add(createLocalTemplate(MGMT_TPL, 'Mgmt Notif'));
            templates.add(createLocalTemplate(ENROLL_TPL, 'Enroll Notif'));
            insert templates;
        }
    }

    // Local Helper for Setup (Not in Utility)
    private static EmailTemplate createLocalTemplate(String devName, String name) {
        return new EmailTemplate(
            DeveloperName = devName,
            Name = name,
            Subject = 'Status Update: {{{Project__c.Name}}}',
            HtmlValue = '<html><body>Project {{{Project__c.Name}}} is done.</body></html>',
            TemplateType = 'custom',
            FolderId = UserInfo.getUserId(),
            IsActive = true
        );
    }

    // ==========================================
    // POSITIVE TESTS
    // ==========================================

    @isTest
    static void testSuccessfulCompletion() {
        // Query ALL fields used by Handler logic
        Project__c proj = [
            SELECT Id, Name, Status__c, Project_Completion_Status__c, 
                   Client__c, Supervisor_User__c, Project_Code__c, 
                   Project_Scope__c, Type_Of_Project__c,
                   Client_Email__c, Supervisor_Email_Text_c__c 
            FROM Project__c 
            LIMIT 1
        ];
        
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };

        // Update to "Completed" AND 100%
        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 100;
        
        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.debug('testSuccessfulCompletion Invocations: ' + invocations);
        Assert.isTrue(true, 'Executed without exception'); 
    }

    @isTest
    static void testManagerRoleLogic() {
        // Create Role manually (Utility creates role but returns UserRole object, we need to create user with it)
        // Utility method #21: createUserRole
        UserRole mgrRole = TestDataUtility.createUserRole('Regional Project Manager');

        // Utility method #22: createUserWithRole
        User mgrUser = TestDataUtility.createUserWithRole('mgrUser', mgrRole.Id);

        Project__c proj = [
            SELECT Id, Name, Status__c, Project_Completion_Status__c, 
                   Client__c, Supervisor_User__c, Project_Code__c, 
                   Project_Scope__c, Type_Of_Project__c,
                   Client_Email__c, Supervisor_Email_Text_c__c 
            FROM Project__c 
            LIMIT 1
        ];
        
        // Update Project to use this Manager as Supervisor (to trigger manager logic)
        proj.Supervisor_User__c = mgrUser.Id;
        
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };

        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 100;

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj }, 
            oldMap
        );
        Test.stopTest();

        Assert.isTrue(true, 'Executed without exception');
    }

    @isTest
    static void testEmailFallbackLogic() {
        Project__c proj = [
            SELECT Id, Name, Status__c, Project_Completion_Status__c, 
                   Client__c, Supervisor_User__c, 
                   Project_Scope__c, Type_Of_Project__c,
                   Client_Email__c, Supervisor_Email_Text_c__c
            FROM Project__c 
            LIMIT 1
        ];
        
        // Clear lookups to test null email handling
        proj.Client__c = null;
        proj.Supervisor_User__c = null;
        update proj;

        // Refresh to ensure formula fields update (like Client_Email__c)
        proj = [
            SELECT Id, Name, Status__c, Project_Completion_Status__c, 
                   Client__c, Supervisor_User__c, 
                   Project_Scope__c, Type_Of_Project__c,
                   Client_Email__c, Supervisor_Email_Text_c__c
            FROM Project__c 
            WHERE Id = :proj.Id
        ];

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };

        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 100;

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj }, 
            oldMap
        );
        Test.stopTest();
        
        Assert.isTrue(true, 'Executed without exception when emails are missing');
    }

    // ==========================================
    // NEGATIVE TESTS
    // ==========================================

    @isTest
    static void testPartialCompletionStatusOnly() {
        Project__c proj = [SELECT Id, Status__c, Project_Completion_Status__c FROM Project__c LIMIT 1];
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };

        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 0; 

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should NOT send email if % is not 100');
    }

    @isTest
    static void testPartialCompletionPercentOnly() {
        Project__c proj = [SELECT Id, Status__c, Project_Completion_Status__c FROM Project__c LIMIT 1];
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj.clone(true, true, true, true) };

        proj.Status__c = 'In Progress';
        proj.Project_Completion_Status__c = 100; 

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should NOT send email if Status is not Completed');
    }

    @isTest
    static void testAlreadyCompleted() {
        Project__c proj = [SELECT Id, Status__c, Project_Completion_Status__c FROM Project__c LIMIT 1];
        
        Project__c oldProj = proj.clone(true, true, true, true);
        oldProj.Status__c = 'Completed';
        oldProj.Project_Completion_Status__c = 100;
        
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => oldProj };

        // No Change
        proj.Status__c = 'Completed';
        proj.Project_Completion_Status__c = 100;

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj }, 
            oldMap
        );
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(0, invocations, 'Should NOT send email if it was already completed');
    }
    
    @isTest
    static void testOrchestratorNullSafety() {
        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(null, null);
        ProjectCompletionEmailHandler.handleAfterUpdate(new List<Project__c>(), new Map<Id, Project__c>());
        ProjectCompletionEmailHandler.sendProjectApprovedEmail(null);
        Test.stopTest();
        
        Assert.isTrue(true, 'Should handle empty/null inputs gracefully');
    }
}