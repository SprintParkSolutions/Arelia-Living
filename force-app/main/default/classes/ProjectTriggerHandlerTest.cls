/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-23-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
public class ProjectTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        User supervisor;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole managerRole = TestDataUtility.createUserRole('Regional Manager');
            UserRole enrollmentRole = TestDataUtility.createUserRole('Enrollment Team');

            TestDataUtility.createUserWithRole('mgr', managerRole.Id);
            TestDataUtility.createUserWithRole('enr', enrollmentRole.Id);
            supervisor = TestDataUtility.createSupervisorUser('sup');

            TestDataUtility.createSpecificEmailTemplate('TEST_Client', 'Client Notif', 'Welcome Client');
            TestDataUtility.createSpecificEmailTemplate('TEST_Sup', 'Sup Notif', 'Project Assigned');

            EmailTemplate mgrT = new EmailTemplate(
                DeveloperName = 'TEST_Manager', Name = 'Mgr Notif',
                Subject = 'Hi {{{ManagerName}}}',
                HtmlValue = 'Body {{{ManagerName}}}',
                TemplateType = 'custom', FolderId = UserInfo.getUserId()
            );
            insert mgrT;

            TestDataUtility.createSpecificEmailTemplate('TEST_Mgmt', 'Mgmt Notif', 'Info for Mgmt');
            TestDataUtility.createSpecificEmailTemplate('TEST_Enr', 'Enrollment Notif', 'Info for Enrollment');
        }

        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com', 'password123');
        Project__c proj = TestDataUtility.createProject('Test Project Code Gen', 50000, client.Id);

        proj.Supervisor_User__c = supervisor.Id;
        proj.Project_Request_Quotation_Type__c = 'Automatic Quotation';
        update proj;
    }

    @IsTest
    static void testAssignProjectCodes() {
        List<Project__c> projects = [SELECT Id, Project_Code__c FROM Project__c];
        
        for (Project__c p : projects) {
            p.Project_Code__c = null;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectTriggerHandler.assignProjectCodes(projects);
            Test.stopTest();
        }

        for (Project__c p : projects) {
            System.assert(String.isNotBlank(p.Project_Code__c), 'Code should be generated');
            System.assert(p.Project_Code__c.startsWith('AL-'), 'Should start with AL-');
        }
    }

    // Added to improve coverage (Hits the 'continue' branch)
    @IsTest
    static void testAssignProjectCodes_SkipExisting() {
        List<Project__c> projects = [SELECT Id, Project_Code__c FROM Project__c];
        
        for (Project__c p : projects) {
            p.Project_Code__c = 'EXISTING-123';
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectTriggerHandler.assignProjectCodes(projects);
            Test.stopTest();
        }

        for (Project__c p : projects) {
            System.assertEquals('EXISTING-123', p.Project_Code__c, 'Existing code should not be overwritten');
        }
    }

    @IsTest
    static void testSendProjectApprovedEmailFullCoverage() {
        List<Project__c> projects = [
            SELECT Id, Name, Client__c, Supervisor_User__c,
                   Project_Code__c, Status__c, Type_Of_Project__c,
                   Project_Scope__c, Project_Request_Quotation_Type__c
            FROM Project__c
        ];

        ProjectTriggerHandler.clientTemplateName = 'TEST_Client';
        ProjectTriggerHandler.supervisorTemplateName = 'TEST_Sup';
        ProjectTriggerHandler.managerTemplateName = 'TEST_Manager';
        ProjectTriggerHandler.mgmtTemplateName = 'TEST_Mgmt';
        ProjectTriggerHandler.enrollmentTemplateName = 'TEST_Enr';

        ProjectTriggerHandler.defaultOwdEmail = 'invalid_email_skip_query@test.com';

        String existingUserEmail = [SELECT Email FROM User WHERE Alias = 'mgr' LIMIT 1].Email;
        ProjectTriggerHandler.mgmtEmailListLabel = existingUserEmail + ', external.partner@gmail.com';

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer startCount = Limits.getEmailInvocations();
            ProjectTriggerHandler.sendProjectApprovedEmail(projects);
            Integer endCount = Limits.getEmailInvocations();
            Test.stopTest();

            System.assert((endCount - startCount) > 0, 'Emails should have been sent.');
        }
    }

    @IsTest
    static void testEmailMissingData() {
        // Test with missing Supervisor to trigger addIfNotNull guarding
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        p.Supervisor_User__c = null;
        update p;
        
        List<Project__c> projects = [
            SELECT Id, Name, Client__c, Supervisor_User__c,
                   Project_Code__c, Status__c, Type_Of_Project__c,
                   Project_Scope__c, Project_Request_Quotation_Type__c
            FROM Project__c
        ];

        ProjectTriggerHandler.supervisorTemplateName = 'TEST_Sup'; // Valid template
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectTriggerHandler.sendProjectApprovedEmail(projects);
            Test.stopTest();
            // No assertion needed; just ensuring no NPE is thrown
        }
    }

    @IsTest
    static void testNullHandlers() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectTriggerHandler.assignProjectCodes(null);
            ProjectTriggerHandler.sendProjectApprovedEmail(null);
            Test.stopTest();
            System.assert(true, 'Should not throw exception');
        }
    }
}