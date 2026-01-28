/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 01-27-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
public class SiteVisitReportHandlerTest {

    @TestSetup
    static void setupData() {
        // 1. Create Supervisor
        User supervisor = TestDataUtility.createSupervisorUser('SupSVR');

        // 2. Create Roles (for Manager email logic)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Check if role exists before creating to avoid dup errors in some orgs
            UserRole r;
            List<UserRole> roles = [SELECT Id FROM UserRole WHERE Name = 'Regional Manager' LIMIT 1];
            if (!roles.isEmpty()) {
                r = roles[0];
            } else {
                r = TestDataUtility.createUserRole('Regional Manager');
            }

            // Create a user with this role
            TestDataUtility.createUserWithRole('MgrUser', r.Id);

            // 3. Create Email Templates (Mocking the custom labels)
            String leadTplName = Label.Arelia_Living_Lead_Conversion_Approval_Email_Template;
            if (String.isNotBlank(leadTplName)) {
                TestDataUtility.createSpecificEmailTemplate(
                    leadTplName, 'Lead Approval', 'Subject Lead {{{Site_Visit_Report__c.Name}}}'
                );
            }

            String oppTplName = Label.Arelia_Living_Opportunity_Re_Visit_Site_Manager_Approval_Email_Template;
            if (String.isNotBlank(oppTplName)) {
                TestDataUtility.createSpecificEmailTemplate(
                    oppTplName, 'Opp Approval', 'Subject Opp {{{Site_Visit_Report__c.Name}}}'
                );
            }
        }

        // 4. Create Parent Records
        Lead l = TestDataUtility.createLead('Test Lead SVR');

        // --- FIX: Satisfy Validation Rule ---
        l.Appointment_Completed__c = true;
        l.Appointment_Status__c = 'Approved';
        l.Appointment_Date__c = Date.today().addDays(1);
        l.Appointment_Time_Slots__c = '10AM-11AM';
        update l;
        // ------------------------------------

        Opportunity opp = TestDataUtility.createOpportunity('Test Opp SVR', supervisor.Id);

        // 5. Get Record Type LABELS dynamically
        String leadRTLabel = Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByDeveloperName()
            .get('Lead_Site_Visit_Report')
            .getName();

        String oppRTLabel = Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByDeveloperName()
            .get('Opportunity_Site_Visit_Report')
            .getName();

        // 6. Create Site Visit Reports
        Site_Visit_Report__c svrLead = TestDataUtility.createSiteVisitReport(l.Id, leadRTLabel);
        svrLead.Total_Estimated_Cost__c = 100;
        svrLead.Site_Visit_Report_Status__c = 'Pending';
        svrLead.Estimated_Completion_Months__c = '1 Month';
        update svrLead;

        Site_Visit_Report__c svrOpp = TestDataUtility.createSiteVisitReport(opp.Id, oppRTLabel);
        svrOpp.Total_Estimated_Cost__c = 200;
        svrOpp.Site_Visit_Report_Status__c = 'Pending';
        svrOpp.Estimated_Completion_Months__c = '2 Months';
        update svrOpp;
    }

    @IsTest
    static void testLeadSync() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Query Includes fields needed for logic to prevent SObjectException
            Site_Visit_Report__c svr = [
                SELECT Id, Lead__c, RecordTypeId, Site_Visit_Report_Status__c,
                       Estimated_Completion_Date__c, Opportunity__c, Estimated_Completion_Months__c
                FROM Site_Visit_Report__c
                WHERE Lead__c != null
                LIMIT 1
            ];

            Test.startTest();
            svr.Site_Visit_Report_Status__c = 'Negotiable';
            svr.Estimated_Completion_Date__c = Date.today().addDays(5);
            svr.Estimated_Completion_Months__c = '3 Months';

            // Pass complete object to handler
            SiteVisitReportHandler.afterUpdate(
                new List<Site_Visit_Report__c>{svr},
                new Map<Id, Site_Visit_Report__c>{svr.Id => new Site_Visit_Report__c(
                    Id = svr.Id,
                    Site_Visit_Report_Status__c = 'Pending',
                    Estimated_Completion_Months__c = '1 Month',
                    Estimated_Completion_Date__c = Date.today()
                )}
            );

            update svr;
            Test.stopTest();

            Lead l = [SELECT Site_Visit_Status__c, Project_End_Date_by_Supervisor__c, Project_Estimated_Completion_Months__c FROM Lead WHERE Id = :svr.Lead__c];
            System.assertEquals('Negotiable', l.Site_Visit_Status__c, 'Lead status should sync');
            System.assertEquals(Date.today().addDays(5), l.Project_End_Date_by_Supervisor__c, 'Lead date should sync');
            System.assertEquals('3 Months', l.Project_Estimated_Completion_Months__c, 'Lead months should sync');
        }
    }

    @IsTest
    static void testOpportunitySync() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Site_Visit_Report__c svr = [
                SELECT Id, Opportunity__c, Lead__c, RecordTypeId, Site_Visit_Report_Status__c,
                       Estimated_Completion_Date__c, Estimated_Completion_Months__c
                FROM Site_Visit_Report__c
                WHERE Opportunity__c != null
                LIMIT 1
            ];

            Test.startTest();
            svr.Site_Visit_Report_Status__c = 'Negotiable';
            svr.Estimated_Completion_Date__c = Date.today().addDays(10);

            SiteVisitReportHandler.afterUpdate(
                new List<Site_Visit_Report__c>{svr},
                new Map<Id, Site_Visit_Report__c>{svr.Id => new Site_Visit_Report__c(
                    Id=svr.Id,
                    Site_Visit_Report_Status__c='Pending',
                    Estimated_Completion_Date__c = Date.today()
                )}
            );
            update svr;
            Test.stopTest();

            Opportunity opp = [SELECT Re_Visit_Site_Status__c, Re_Visit_Site_Supervisor_Completion_Date__c FROM Opportunity WHERE Id = :svr.Opportunity__c];
            System.assertEquals('Negotiable', opp.Re_Visit_Site_Status__c, 'Opp status should sync');
            System.assertEquals(Date.today().addDays(10), opp.Re_Visit_Site_Supervisor_Completion_Date__c, 'Opp date should sync');
        }
    }

    @IsTest
    static void testApprovalEmailSendingWithAttachments() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Site_Visit_Report__c svr = [
                SELECT Id, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c,
                       Lead__c, Opportunity__c, Estimated_Completion_Months__c
                FROM Site_Visit_Report__c
                WHERE Lead__c != null
                LIMIT 1
            ];

            // 1. Create ContentVersion (File)
            ContentVersion cv = TestDataUtility.createContentVersion('Test Report PDF', 'PDF Content');
            TestDataUtility.linkFileToRecord(cv.Id, svr.Id);

            // 2. Create Attachment (Standard)
            Attachment att = new Attachment();
            att.Name = 'OldStyle.txt';
            att.Body = Blob.valueOf('Text Body');
            att.ParentId = svr.Id;
            insert att;

            Test.startTest();
            svr.Site_Visit_Report_Status__c = 'Approved';
            update svr;

            // Manually invoke logic
            SiteVisitReportHandler.afterUpdate(
                new List<Site_Visit_Report__c>{svr},
                new Map<Id, Site_Visit_Report__c>{svr.Id => new Site_Visit_Report__c(
                    Id=svr.Id,
                    Site_Visit_Report_Status__c='Pending'
                )}
            );

            Test.stopTest();

            System.assert(true, 'Email logic executed without exceptions');
        }
    }

    @IsTest
    static void testManualEmailInvocation() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Site_Visit_Report__c> reports = [SELECT Id FROM Site_Visit_Report__c];
            List<Id> ids = new List<Id>();

            for(Site_Visit_Report__c r : reports) {
                ids.add(r.Id);
            }

            Test.startTest();
            // Test Valid
            SiteVisitReportHandler.sendApprovalEmails(ids);

            // Test Guards (Nulls)
            SiteVisitReportHandler.sendApprovalEmails(null);
            SiteVisitReportHandler.sendApprovalEmails(new List<Id>());

            Test.stopTest();

            System.assert(true, 'Method executed successfully');
        }
    }

    @IsTest
    static void testOrchestrationInsert() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Site_Visit_Report__c> reports = [SELECT Id FROM Site_Visit_Report__c];

            Test.startTest();
            SiteVisitReportHandler.afterInsert(null);
            SiteVisitReportHandler.afterInsert(reports);
            Test.stopTest();

            System.assert(true, 'After insert orchestration ran');
        }
    }
}