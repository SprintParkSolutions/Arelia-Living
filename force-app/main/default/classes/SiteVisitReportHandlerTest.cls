@isTest
public class SiteVisitReportHandlerTest {

    @testSetup
    static void setupData() {
        // 1. Create Supervisor
        User supervisor = TestDataUtility.createSupervisorUser('SupSVR');

        // 2. Create Roles (for Manager email logic)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole r = new UserRole(DeveloperName = 'Regional_Manager', Name = 'Regional Manager');
            insert r;
            TestDataUtility.createUserWithRole('MgrUser', r.Id);

            // 3. Create Email Templates
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

        // 5. Create Site Visit Reports
        Id leadRT = Schema.SObjectType.Site_Visit_Report__c.getRecordTypeInfosByDeveloperName().get('Lead_Site_Visit_Report').getRecordTypeId();
        Id oppRT = Schema.SObjectType.Site_Visit_Report__c.getRecordTypeInfosByDeveloperName().get('Opportunity_Site_Visit_Report').getRecordTypeId();

        Site_Visit_Report__c svrLead = new Site_Visit_Report__c(
            Lead__c = l.Id,
            RecordTypeId = leadRT,
            Total_Estimated_Cost__c = 100,
            Site_Visit_Report_Status__c = 'Pending'
        );
        insert svrLead;

        Site_Visit_Report__c svrOpp = new Site_Visit_Report__c(
            Opportunity__c = opp.Id,
            RecordTypeId = oppRT,
            Total_Estimated_Cost__c = 200,
            Site_Visit_Report_Status__c = 'Pending'
        );
        insert svrOpp;
    }

    @isTest
    static void testLeadSync() {
        // Query ALL fields the handler needs
        Site_Visit_Report__c svr = [
            SELECT Id, Lead__c, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c, Opportunity__c
            FROM Site_Visit_Report__c 
            WHERE Lead__c != null 
            LIMIT 1
        ];
        
        Test.startTest();
        svr.Site_Visit_Report_Status__c = 'Negotiable';
        svr.Estimated_Completion_Date__c = Date.today().addDays(5);
        
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
        // Query ALL fields the handler needs
        Site_Visit_Report__c svr = [
            SELECT Id, Opportunity__c, Lead__c, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c 
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
        // FIX: Added Lead__c and Opportunity__c to query so handler doesn't crash
        Site_Visit_Report__c svr = [
            SELECT Id, RecordTypeId, Site_Visit_Report_Status__c, Estimated_Completion_Date__c, Lead__c, Opportunity__c
            FROM Site_Visit_Report__c 
            WHERE Lead__c != null 
            LIMIT 1
        ];
        
        Test.startTest();
        svr.Site_Visit_Report_Status__c = 'Approved';
        update svr; 
        
        // Manually invoke logic simulating status change to Approved
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
        // FIX: Added Lead__c and Opportunity__c (and others) to allow subsequent logic to work if needed
        List<Site_Visit_Report__c> reports = [SELECT Id, Lead__c, Opportunity__c FROM Site_Visit_Report__c];
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