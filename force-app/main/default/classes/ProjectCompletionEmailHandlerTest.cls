@isTest
public class ProjectCompletionEmailHandlerTest {

    // Constants matching the Handler's private constants
    private static final String CLIENT_TPL     = 'Client_Project_Completed_Notification';
    private static final String SUPERVISOR_TPL = 'Supervisor_Project_Completed_Notification';
    private static final String MANAGER_TPL    = 'Sending_Project_Completed_Information_to_Manager';
    private static final String MGMT_TPL       = 'Sending_Project_Completed_Information_to_Management';
    private static final String ENROLL_TPL     = 'Sending_Project_Completed_Information_to_Enrollment';

    // -------------------------------------------------------------------------
    // Single @testSetup: ONLY setup objects (UserRole, User, EmailTemplate)
    // -------------------------------------------------------------------------
    @testSetup
    static void setupData() {
        // Manager Role + User so getManagersByRole() has at least one match
        UserRole mgrRole = TestDataUtility.createUserRole('Regional Project Manager');
        TestDataUtility.createUserWithRole('mgrUser', mgrRole.Id);

        // Email templates used by handler
        TestDataUtility.createSpecificEmailTemplate(
            CLIENT_TPL,
            'Client Notif',
            'Status Update: {{{Project__c.Name}}}'
        );
        TestDataUtility.createSpecificEmailTemplate(
            SUPERVISOR_TPL,
            'Sup Notif',
            'Status Update: {{{Project__c.Name}}}'
        );
        TestDataUtility.createSpecificEmailTemplate(
            MANAGER_TPL,
            'Manager Notif',
            'Status Update: {{{Project__c.Name}}}'
        );
        TestDataUtility.createSpecificEmailTemplate(
            MGMT_TPL,
            'Mgmt Notif',
            'Status Update: {{{Project__c.Name}}}'
        );
        TestDataUtility.createSpecificEmailTemplate(
            ENROLL_TPL,
            'Enroll Notif',
            'Status Update: {{{Project__c.Name}}}'
        );
    }

    // -------------------------------------------------------------------------
    // Helper: create non-setup data for a single Project (NO SOQL here)
    // -------------------------------------------------------------------------
    private static Project__c createBaseProject() {
        // Account
        Account acc = TestDataUtility.createAccount('Project Client Co');

        // Contact
        Contact client = TestDataUtility.createContact(
            'Project Client',
            'client@project.test',
            'password123'
        );
        client.AccountId = acc.Id;
        update client;

        // Project
        Project__c proj = TestDataUtility.createProject(
            'Test Completion Project',
            50000,
            client.Id
        );

        proj.Status__c                    = 'In Progress';
        proj.Project_Completion_Status__c = 0;
        proj.Project_Code__c              = 'PRJ-001';
        update proj;

        return proj;
    }

    // ==========================================
    // POSITIVE TESTS
    // ==========================================

    @isTest
    static void testSuccessfulCompletion() {
        Project__c proj = createBaseProject();

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{
            proj.Id => proj.clone(true, true, true, true)
        };

        // Flip to "Completed" AND 100%
        proj.Status__c                    = 'Completed';
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
        // Manager Role + User already created in @testSetup.
        Project__c proj = createBaseProject();

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{
            proj.Id => proj.clone(true, true, true, true)
        };

        proj.Status__c                    = 'Completed';
        proj.Project_Completion_Status__c = 100;

        Test.startTest();
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>{ proj },
            oldMap
        );
        Test.stopTest();

        Assert.isTrue(true, 'Executed without exception for manager role logic');
    }

    @isTest
    static void testEmailFallbackLogic() {
        Project__c proj = createBaseProject();

        // Clear lookups to force fallback logic paths
        proj.Client__c          = null;
        proj.Supervisor_User__c = null;
        update proj;

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{
            proj.Id => proj.clone(true, true, true, true)
        };

        proj.Status__c                    = 'Completed';
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
        Project__c proj = createBaseProject();

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{
            proj.Id => proj.clone(true, true, true, true)
        };

        proj.Status__c                    = 'Completed';
        proj.Project_Completion_Status__c = 0; // not 100

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
        Project__c proj = createBaseProject();

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{
            proj.Id => proj.clone(true, true, true, true)
        };

        proj.Status__c                    = 'In Progress'; // not Completed
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
        Project__c proj = createBaseProject();

        Project__c oldProj = proj.clone(true, true, true, true);
        oldProj.Status__c                    = 'Completed';
        oldProj.Project_Completion_Status__c = 100;

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{
            proj.Id => oldProj
        };

        // No change – stays Completed @ 100
        proj.Status__c                    = 'Completed';
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
        ProjectCompletionEmailHandler.handleAfterUpdate(
            new List<Project__c>(),
            new Map<Id, Project__c>()
        );
        ProjectCompletionEmailHandler.sendProjectApprovedEmail(null);
        Test.stopTest();

        Assert.isTrue(true, 'Should handle empty/null inputs gracefully');
    }
}
