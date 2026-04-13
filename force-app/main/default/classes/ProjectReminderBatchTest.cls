/**
 * @description
 *  Unit tests for ProjectReminderBatch and ProjectReminderBatchScheduler.
 *
 * Notes:
 *  - Uses TestDataUtility helper methods for non-setup data (Contact, Project__c).
 *  - Does NOT perform any setup-object DML (no EmailTemplate, UserRole, etc.).
 *  - Relies on an existing EmailTemplate whose DeveloperName =
 *      Label.Arelia_Living_Project_Reminder_Template
 *    which should exist in the org for the batch to work in production.
 *  - Runs the batch end-to-end via Database.executeBatch.
 */
@IsTest(SeeAllData=true)
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexUnitTestShouldNotUseSeeAllDataTrue,PMD.ApexCRUDViolation,PMD.ApexSharingViolations')
private class ProjectReminderBatchTest {

    /**
     * @description
     *  Helper to get the effective reminder interval using the same logic
     *  as the production method getReminderIntervalDays().
     *  (Reads the label and falls back to 15 days.)
     */
    private static Integer getEffectiveIntervalFromLabel() {
        Integer interval = 15;
        String raw = Label.Arelia_Living_Project_Reminder_Days;

        if (!String.isBlank(raw)) {
            try {
                Integer parsed = Integer.valueOf(raw.trim());
                if (parsed != null && parsed > 0) {
                    interval = parsed;
                }
            } catch (Exception e) {
                interval = 15;
            }
        }
        return interval;
    }

    /**
     * @description
     *  Creates a valid Project__c for the batch query:
     *  - Status__c = 'In Progress'
     *  - Start_Date__c != null
     *  - Estimated_End_Date__c != null (formula driven by duration)
     *  - Within reminder interval so that an email SHOULD be sent.
     */
    private static Project__c createProjectForReminder(Id clientContactId, Id supervisorUserId) {
        // Base project from utility (In Progress, Active, budget, client)
        Project__c proj = TestDataUtility.createProject(
            'Reminder Project',
            50000,
            clientContactId
        );

        // Valid picklist for Estimated_Project_Duration__c
        Schema.DescribeFieldResult durDescribe =
            Project__c.Estimated_Project_Duration__c.getDescribe();
        List<Schema.PicklistEntry> durValues = durDescribe.getPicklistValues();
        String anyDuration = durValues.isEmpty() ? null : durValues[0].getValue();

        // Valid picklist for Type_Of_Project__c
        Schema.DescribeFieldResult typeDescribe =
            Project__c.Type_Of_Project__c.getDescribe();
        List<Schema.PicklistEntry> typeValues = typeDescribe.getPicklistValues();
        String anyType = typeValues.isEmpty() ? null : typeValues[0].getValue();

        Integer interval = getEffectiveIntervalFromLabel();

        proj.Start_Date__c                  = Date.today().addDays(-interval);
        proj.Supervisor_User__c            = supervisorUserId;
        proj.Type_Of_Project__c            = anyType;
        proj.Estimated_Project_Duration__c = anyDuration;
        proj.Project_Completion_Status__c  = 50; // for completion formatting

        update proj;

        return proj;
    }

    /**
     * @description
     *  Creates a Project__c that will be SKIPPED by the reminder logic:
     *  - Start_Date__c = today  → daysFromStart = 0 (<= 0 condition)
     *  - So it will hit the "skip due to date conditions" branch.
     */
    private static Project__c createProjectToSkip(Id clientContactId, Id supervisorUserId) {
        Project__c proj = TestDataUtility.createProject(
            'Skip Project',
            40000,
            clientContactId
        );

        // Same picklists as the valid project
        Schema.DescribeFieldResult durDescribe =
            Project__c.Estimated_Project_Duration__c.getDescribe();
        List<Schema.PicklistEntry> durValues = durDescribe.getPicklistValues();
        String anyDuration = durValues.isEmpty() ? null : durValues[0].getValue();

        Schema.DescribeFieldResult typeDescribe =
            Project__c.Type_Of_Project__c.getDescribe();
        List<Schema.PicklistEntry> typeValues = typeDescribe.getPicklistValues();
        String anyType = typeValues.isEmpty() ? null : typeValues[0].getValue();

        proj.Start_Date__c                  = Date.today(); // daysFromStart = 0 → skip
        proj.Supervisor_User__c            = supervisorUserId;
        proj.Type_Of_Project__c            = anyType;
        proj.Estimated_Project_Duration__c = anyDuration;
        proj.Project_Completion_Status__c  = 20;

        update proj;

        return proj;
    }

    /**
     * @description
     *  Covers start(), execute(), and finish() of ProjectReminderBatch.
     */
    @IsTest
    static void testBatchSendsReminderEmails() {
        Id currentUserId = UserInfo.getUserId();

        // --- Verify that the template exists in org (defensive check) ---
        String devName = Label.Arelia_Living_Project_Reminder_Template;
        EmailTemplate tpl = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :devName
            LIMIT 1
        ];
        System.assertNotEquals(
            null,
            tpl,
            'EmailTemplate with DeveloperName from label must exist in org for this batch.'
        );

        // --- Client contact (non-setup object, safe) ---
        Contact client = TestDataUtility.createContact(
            'Client Test',
            'client+' + DateTime.now().getTime() + '@example.com',
            'testPassword'
        );

        // --- Projects: one valid, one to be skipped ---
        Project__c projOk   = createProjectForReminder(client.Id, currentUserId);
        Project__c projSkip = createProjectToSkip(client.Id, currentUserId);

        Test.startTest();
        // Run the batch end-to-end; this will call start(), execute(), finish()
        Database.executeBatch(new ProjectReminderBatch(), 200);
        Test.stopTest();

        // There should be at least one Messaging.sendEmail invocation
        System.assert(
            Limits.getEmailInvocations() > 0,
            'ProjectReminderBatch should send at least one email for a valid project.'
        );
    }

    /**
     * @description
     *  Covers the scheduler class ProjectReminderBatchScheduler.
     */
    @IsTest
    static void testSchedulerEnqueuesBatchJob() {
        Integer preJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];

        Test.startTest();
        ProjectReminderBatchScheduler scheduler = new ProjectReminderBatchScheduler();
        scheduler.execute(null);
        Test.stopTest();

        Integer postJobs = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
        ];

        System.assert(
            postJobs > preJobs,
            'Scheduler should enqueue at least one BatchApex job.'
        );
    }
}
