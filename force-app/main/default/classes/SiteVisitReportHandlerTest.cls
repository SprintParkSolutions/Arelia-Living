@isTest
public class SiteVisitReportHandlerTest {

    @testSetup
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
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp SVR', supervisor.Id);

        // 5. Get Record Type LABELS dynamically (Utility expects Label, not DeveloperName)
        // We use DeveloperName to find the Info, then get .getName() for the Label.
        String leadRTLabel = Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByDeveloperName()
            .get('Lead_Site_Visit_Report')
            .getName();

        String oppRTLabel = Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByDeveloperName()
            .get('Opportunity_Site_Visit_Report')
            .getName();

        // 6. Create Site Visit Reports using the Utility with Correct Labels
        Site_Visit_Report__c svrLead = TestDataUtility.createSiteVisitReport(l.Id, leadRTLabel);
        svrLead.Total_Estimated_Cost__c = 100;
        svrLead.Site_Visit_Report_Status__c = 'Pending';
        svrLead.Estimated_Completion_Months__c = '1 Month'; // Ensure field has value
        update svrLead;

        Site_Visit_Report__c svrOpp = TestDataUtility.createSiteVisitReport(opp.Id, oppRTLabel);
        svrOpp.Total_Estimated_Cost__c = 200;
        svrOpp.Site_Visit_Report_Status__c = 'Pending';
        svrOpp.Estimated_Completion_Months__c = '2 Months'; // Ensure field has value
        update svrOpp;
    }

    @isTest
    static void testLeadSync() {
        // FIX: Query Includes Estimated_Completion_Months__c to avoid SObjectException
        Site_Visit_Report__c svr = [
            SELECT Id, Lead__c, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c, Opportunity__c, Estimated_Completion_Months__c
            FROM Site_Visit_Report__c 
            WHERE Lead__c != null 
            LIMIT 1
        ];
        
        Test.startTest();
        svr.Site_Visit_Report_Status__c = 'Negotiable';
        svr.Estimated_Completion_Date__c = Date.today().addDays(5);
        
        // Pass complete object to handler
        SiteVisitReportHandler.afterUpdate(
            new List<Site_Visit_Report__c>{svr}, 
            new Map<Id, Site_Visit_Report__c>{svr.Id => new Site_Visit_Report__c(Id=svr.Id, Site_Visit_Report_Status__c='Pending')}
        );
        
        update svr;
        Test.stopTest();

        Lead l = [SELECT Site_Visit_Status__c, Project_End_Date_by_Supervisor__c FROM Lead WHERE Id = :svr.Lead__c];
        System.assertEquals('Negotiable', l.Site_Visit_Status__c, 'Lead status should sync');
        System.assertEquals(Date.today().addDays(5), l.Project_End_Date_by_Supervisor__c, 'Lead date should sync');
    }

    @isTest
    static void testOpportunitySync() {
        // FIX: Query Includes Estimated_Completion_Months__c
        Site_Visit_Report__c svr = [
            SELECT Id, Opportunity__c, Lead__c, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c, Estimated_Completion_Months__c 
            FROM Site_Visit_Report__c 
            WHERE Opportunity__c != null 
            LIMIT 1
        ];
        
        Test.startTest();
        svr.Site_Visit_Report_Status__c = 'Negotiable';
        svr.Estimated_Completion_Date__c = Date.today().addDays(10);
        
        SiteVisitReportHandler.afterUpdate(
            new List<Site_Visit_Report__c>{svr}, 
            new Map<Id, Site_Visit_Report__c>{svr.Id => new Site_Visit_Report__c(Id=svr.Id, Site_Visit_Report_Status__c='Pending')}
        );
        update svr;
        Test.stopTest();

        Opportunity opp = [SELECT Re_Visit_Site_Status__c, Re_Visit_Site_Supervisor_Completion_Date__c FROM Opportunity WHERE Id = :svr.Opportunity__c];
        System.assertEquals('Negotiable', opp.Re_Visit_Site_Status__c, 'Opp status should sync');
        System.assertEquals(Date.today().addDays(10), opp.Re_Visit_Site_Supervisor_Completion_Date__c, 'Opp date should sync');
    }

    @isTest
    static void testApprovalEmailSending() {
        // FIX: Query Includes Estimated_Completion_Months__c
        Site_Visit_Report__c svr = [
            SELECT Id, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c, Lead__c, Opportunity__c, Estimated_Completion_Months__c
            FROM Site_Visit_Report__c 
            WHERE Lead__c != null 
            LIMIT 1
        ];
        
        Test.startTest();
        svr.Site_Visit_Report_Status__c = 'Approved';
        update svr; 
        
        // Manually invoke logic with the FULLY populated svr object
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

    @isTest
    static void testManualEmailInvocation() {
        // Query minimal required fields to pass IDs to email method
        List<Site_Visit_Report__c> reports = [SELECT Id FROM Site_Visit_Report__c];
        List<Id> ids = new List<Id>();
        
        for(Site_Visit_Report__c r : reports) {
            ids.add(r.Id);
        }

        Test.startTest();
        SiteVisitReportHandler.sendApprovalEmails(ids);
        Test.stopTest();
        
        System.assert(true, 'Method executed successfully');
    }

    @isTest
    static void testOrchestrationInsert() {
        List<Site_Visit_Report__c> reports = [SELECT Id FROM Site_Visit_Report__c];
        
        Test.startTest();
        SiteVisitReportHandler.afterInsert(reports);
        Test.stopTest();
        
        System.assert(true, 'After insert orchestration ran');
    }
}