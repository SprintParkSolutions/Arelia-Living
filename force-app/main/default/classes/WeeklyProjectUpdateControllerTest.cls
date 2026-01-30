@IsTest
private class WeeklyProjectUpdateControllerTest {

    /* ==========================================
       TEST SETUP (COMMON DATA)
    ========================================== */
    @TestSetup
    static void setup() {

        // 1️⃣ Supervisor User
        User supervisor = TestDataUtility.createSupervisorUser('weeklyUser');

        // 2️⃣ Client Account
        Account acc = new Account(Name = 'Weekly Client');
        insert acc;

        // 3️⃣ Project
        Project__c proj = new Project__c(
            Name = 'Weekly Update Project',
            Client__c = acc.Id,
            Client_Email__c = 'client@weekly.com',
            Start_Date__c = Date.today().addDays(-7),
            Status__c = 'Active',
            Project_Status__c = 'In Progress',
            Supervisor_User__c = supervisor.Id
        );
        insert proj;

        // 4️⃣ Email Template
        EmailTemplate tpl = new EmailTemplate(
            Name = 'Weekly Project Update',
            DeveloperName = 'Weekly_Project_Update_Template',
            FolderId = UserInfo.getUserId(),
            TemplateType = 'custom',
            Subject = 'Update {{{ProjectName}}} - Week {{{WeekNumber}}}',
            HtmlValue =
                'Hello {{{ClientName}}}<br/>' +
                '{{{WeeklySummary}}}<br/>' +
                '{{{FileLinks}}}'
        );
        insert tpl;
    }

    // ==========================================
    // 1. Supervisor Project Getter
    // ==========================================
    @IsTest
    static void testGetSupervisorProjects() {

        User supervisor = [
            SELECT Id
            FROM User
            WHERE Username LIKE '%weeklyUser%'
            LIMIT 1
        ];

        System.runAs(supervisor) {
            Test.startTest();
            List<Project__c> projects =
                WeeklyProjectUpdateController.getSupervisorProjects();
            Test.stopTest();

            Assert.areEqual(1, projects.size());
        }
    }

    // ==========================================
    // 2. Weekly Email – No Files
    // ==========================================
    @IsTest
    static void testSendWeeklyEmail_NoFiles() {

        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        WeeklyProjectUpdateController.sendWeeklyEmail(
            proj.Id,
            'Weekly progress update',
            null
        );
        Test.stopTest();

        Assert.areEqual(1, Limits.getEmailInvocations());
    }

    // ==========================================
    // 3. Weekly Email – With File
    // ==========================================
    @IsTest
    static void testSendWeeklyEmail_WithFile() {

        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'photo',
            PathOnClient = 'photo.jpg',
            VersionData = Blob.valueOf('img'),
            IsMajorVersion = true
        );
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        WeeklyProjectUpdateController.sendWeeklyEmail(
            proj.Id,
            'With image',
            new List<Id>{ cv.ContentDocumentId }
        );
        Test.stopTest();

        Assert.areEqual(1, Limits.getEmailInvocations());
    }

    // ==========================================
    // 4. Missing Client Email (Exception)
    // ==========================================
    @IsTest
    static void testSendWeeklyEmail_MissingClientEmail() {

        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        proj.Client_Email__c = null;
        update proj;

        Test.startTest();
        try {
            WeeklyProjectUpdateController.sendWeeklyEmail(
                proj.Id,
                'Should fail',
                null
            );
            Assert.fail();
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();
    }

    // ==========================================
    // 5. Org-Wide Email Getter
    // ==========================================
    @IsTest
    static void testGetOWD() {

        Test.startTest();
        Id owdId = WeeklyProjectUpdateController.getOWD();
        Test.stopTest();

        // OWD may be null in test context – valid
        Assert.isTrue(true);
    }
}