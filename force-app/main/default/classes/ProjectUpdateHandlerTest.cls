/**
 * @description Test class for ProjectUpdateHandler.
 * Covers positive scenarios, negative scenarios, and guard clauses.
 */
@IsTest
public class ProjectUpdateHandlerTest {

    /**
     * @description Helper to get Client Template DeveloperName dynamically.
     * @return String The DeveloperName or a fallback.
     */
    private static String getClientTemplateDevName() {
        String labelVal = Label.Arelia_Living_Project_Status_Update_Lead_Template;
        return String.isNotBlank(labelVal) ? labelVal : 'Test_Client_Template';
    }

    /**
     * @description Helper to get Supervisor Template DeveloperName dynamically.
     * @return String The DeveloperName or a fallback.
     */
    private static String getSupervisorTemplateDevName() {
        String labelVal = Label.Arelia_Living_Project_Status_Update_Supervisor_Template;
        return String.isNotBlank(labelVal) ? labelVal : 'Test_Supervisor_Template';
    }

    /**
     * @description Sets up the test data including Users, Contacts, Projects, and Templates.
     */
    @TestSetup
    static void setupData() {
        User supervisor = TestDataUtility.createSupervisorUser('supUser');
        TestDataUtility.createContact('Dummy Contact', 'dummy@arelia.test', 'pass123');
        Contact client = TestDataUtility.createContact('Real Client', 'client@arelia.test', 'pass123');

        Project__c proj = TestDataUtility.createProject('Test Project Coverage', 10000, client.Id);
        proj.Supervisor_User__c = supervisor.Id;
        proj.Project_Completion_Status__c = 0;

        // This update triggers the handler once during setup
        update proj;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            createMockTemplate(getClientTemplateDevName());
            createMockTemplate(getSupervisorTemplateDevName());
        }
    }

    /**
     * @description Helper to insert a mock EmailTemplate if it doesn't already exist.
     * @param devName The DeveloperName of the template to create.
     */
    private static void createMockTemplate(String devName) {
        List<EmailTemplate> existing = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName];
        if (!existing.isEmpty()) {
            return;
        }

        EmailTemplate t = new EmailTemplate();
        t.isActive = true;
        t.Name = devName;
        t.DeveloperName = devName;
        t.TemplateType = 'text';
        t.FolderId = UserInfo.getUserId();
        t.Subject = 'Status Update: {{Project__c.Name}}';
        t.Body = 'Project status is now {{Project__c.Project_Completion_Status__c}}';
        insert t;
    }

    /**
     * @description Positive Test: Calls the Handler logic directly with mocked formula fields
     * to ensure emails are prepared and sent.
     */
    @IsTest
    static void testAfterUpdateDirectCallWithMockedFormulas() {
        Project__c proj = [SELECT Id, Name, Client__c, Supervisor_User__c FROM Project__c LIMIT 1];
        Contact client = [SELECT Email FROM Contact WHERE Id = :proj.Client__c];
        User supervisor = [SELECT Email FROM User WHERE Id = :proj.Supervisor_User__c];

        Map<Id, Project__c> oldMap = new Map<Id, Project__c>();
        Project__c oldProj = proj.clone(true, true, true, true);
        oldProj.Project_Completion_Status__c = 0;
        oldMap.put(oldProj.Id, oldProj);

        Project__c newProj = proj.clone(true, true, true, true);
        newProj.Project_Completion_Status__c = 50;

        // Mock Formula Fields via JSON
        Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(newProj));
        dataMap.put('Client_Email__c', client.Email);
        dataMap.put('Supervisor_Email_Text_c__c', supervisor.Email);
        String jsonString = JSON.serialize(dataMap);
        Project__c newProjMock = (Project__c) JSON.deserialize(jsonString, Project__c.class);

        List<Project__c> newList = new List<Project__c>{ newProjMock };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer emailsBefore = Limits.getEmailInvocations();
            ProjectUpdateHandler.afterUpdate(newList, oldMap);
            Integer emailsAfter = Limits.getEmailInvocations();
            Test.stopTest();

            System.assertEquals(1, emailsAfter - emailsBefore, 'One batch of emails should be sent.');
        }
    }

    /**
     * @description Negative Test: Verifies that no emails are sent if the required EmailTemplates are missing.
     */
    @IsTest
    static void testNegativeMissingTemplates() {
        Project__c proj = [SELECT Id, Client_Email__c, Supervisor_Email_Text_c__c FROM Project__c LIMIT 1];
        List<Project__c> projs = new List<Project__c>{ proj };

        Set<String> targetDevNames = new Set<String>{
            getClientTemplateDevName(),
            getSupervisorTemplateDevName()
        };

        List<EmailTemplate> testTemplates = [SELECT Id FROM EmailTemplate WHERE DeveloperName IN :targetDevNames];
        if (!testTemplates.isEmpty()) {
            delete testTemplates;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer emailsBefore = Limits.getEmailInvocations();

            ProjectUpdateHandler.sendProjectStatusUpdateEmails(projs);

            Integer emailsAfter = Limits.getEmailInvocations();
            Test.stopTest();

            System.assertEquals(0, emailsAfter - emailsBefore, 'No emails should send when templates are missing');
        }
    }

    /**
     * @description Negative Test: Verifies that no emails are sent if the dummy contact is missing.
     * Deletes ALL contacts to ensure the loose query in the handler returns nothing.
     */
    @IsTest
    static void testNegativeMissingContact() {
        Project__c proj = [SELECT Id, Client_Email__c, Supervisor_Email_Text_c__c FROM Project__c LIMIT 1];
        List<Project__c> projs = new List<Project__c>{ proj };

        // Delete ALL contacts so getSharedDummyContact() returns null
        delete [SELECT Id FROM Contact];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer emailsBefore = Limits.getEmailInvocations();

            ProjectUpdateHandler.sendProjectStatusUpdateEmails(projs);

            Integer emailsAfter = Limits.getEmailInvocations();
            Test.stopTest();

            System.assertEquals(0, emailsAfter - emailsBefore, 'No emails should send when dummy contact is missing');
        }
    }

    /**
     * @description Test: Verifies behavior when the old record is missing from the map (Orphaned Record).
     */
    @IsTest
    static void testOrphanedOldRecord() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        List<Project__c> newList = new List<Project__c>{ proj };
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer emailsBefore = Limits.getEmailInvocations();
            ProjectUpdateHandler.afterUpdate(newList, oldMap);
            Integer emailsAfter = Limits.getEmailInvocations();
            Test.stopTest();

            System.assertEquals(0, emailsAfter - emailsBefore, 'Orphaned record check failed');
        }
    }

    /**
     * @description Test: Verifies that no emails are sent if the status field has not changed.
     */
    @IsTest
    static void testNoStatusChange() {
        Project__c proj = [SELECT Id, Project_Completion_Status__c FROM Project__c LIMIT 1];
        Map<Id, Project__c> oldMap = new Map<Id, Project__c>{ proj.Id => proj };
        List<Project__c> newList = new List<Project__c>{ proj };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer emailsBefore = Limits.getEmailInvocations();
            ProjectUpdateHandler.afterUpdate(newList, oldMap);
            Integer emailsAfter = Limits.getEmailInvocations();
            Test.stopTest();

            System.assertEquals(0, emailsAfter - emailsBefore, 'Status unchanged check failed');
        }
    }

    /**
     * @description Test: Verifies that guard clauses handle null inputs gracefully.
     */
    @IsTest
    static void testGuardClausesAndNulls() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            ProjectUpdateHandler.afterUpdate(null, null);
            ProjectUpdateHandler.afterUpdate(new List<Project__c>(), null);
            ProjectUpdateHandler.sendProjectStatusUpdateEmails(null);
            ProjectUpdateHandler.sendProjectStatusUpdateEmails(new List<Project__c>());

            List<Project__c> dirtyList = new List<Project__c>();
            dirtyList.add(null);
            ProjectUpdateHandler.sendProjectStatusUpdateEmails(dirtyList);
            Test.stopTest();

            System.assert(true, 'Guard clauses executed successfully');
        }
    }
}