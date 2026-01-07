@isTest
public class ProjectTriggerHelperTest {

    @testSetup
    static void setupData() {
        User supervisor;
        System.runAs(new User(Id = UserInfo.getUserId())) {
             UserRole managerRole = TestDataUtility.createUserRole('Regional Manager');
             TestDataUtility.createUserWithRole('mgr', managerRole.Id);
             supervisor = TestDataUtility.createSupervisorUser('sup');
        }

        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com');

        List<Project__c> projects = new List<Project__c>();
        
        // Project 0: For Success Scenario
        Project__c p1 = TestDataUtility.createProject('Success Project');
        p1.Client__c = client.Id;
        p1.Supervisor_User__c = supervisor.Id;
        p1.Project_Completion_Status__c = 0; 
        projects.add(p1);

        // Project 1: For Project Failure Scenario
        Project__c p2 = TestDataUtility.createProject('Fail Project Own Status');
        p2.Client__c = client.Id;
        p2.Supervisor_User__c = supervisor.Id;
        projects.add(p2);

        // Project 2: For Vendor Failure Scenario
        Project__c p3 = TestDataUtility.createProject('Fail Project Vendor');
        p3.Client__c = client.Id;
        p3.Supervisor_User__c = supervisor.Id;
        projects.add(p3);

        update projects;
    }

    private static Vendor_Assignment__c createVA(Id projectId, String status, Decimal completion) {
        Vendor_Assignment__c va = new Vendor_Assignment__c();
        va.Project__c = projectId;
        va.Status__c = status;
        va.Completion__c = completion;
        insert va;
        return va;
    }

    @isTest
    static void testCompletionSuccess() {
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Success Project' LIMIT 1];

        // Valid: 'Completed' exists in your picklist
        createVA(p.Id, 'Completed', 100);

        Test.startTest();
        p.Project_Completion_Status__c = 100;
        p.Status__c = 'Completed';
        update p;
        Test.stopTest();

        Project__c result = [SELECT Status__c FROM Project__c WHERE Id = :p.Id];
        System.assertEquals('Completed', result.Status__c, 'Project should be updated successfully');
    }

    @isTest
    static void testFailProjectIncomplete() {
        // RENAMED: Removed underscores to satisfy PMD
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Own Status' LIMIT 1];

        createVA(p.Id, 'Completed', 100);

        Test.startTest();
        try {
            p.Project_Completion_Status__c = 99;
            p.Status__c = 'Completed';
            update p;
            System.assert(false, 'Should have thrown an exception regarding Project Completion Status');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Project Completion Status'), 'Error should mention Project Completion Status');
        }
        Test.stopTest();
    }

    @isTest
    static void testFailVendorIncomplete() {
        // RENAMED: Removed underscores to satisfy PMD
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Vendor' LIMIT 1];

        // Use valid picklist value 'In-Progress'
        createVA(p.Id, 'In-Progress', 50);

        Test.startTest();
        try {
            p.Project_Completion_Status__c = 100;
            p.Status__c = 'Completed';
            update p;
            System.assert(false, 'Should have thrown an exception regarding Vendor Assignments');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Vendor Assignments'), 'Error should mention Vendor Assignments');
        }
        Test.stopTest();
    }

    @isTest
    static void testFailVendorStatusMismatch() {
        // RENAMED: Removed underscores to satisfy PMD
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Vendor' LIMIT 1];

        // Use valid picklist value 'Initiated'
        createVA(p.Id, 'Initiated', 100);

        Test.startTest();
        try {
            p.Project_Completion_Status__c = 100;
            p.Status__c = 'Completed';
            update p;
            System.assert(false, 'Should fail if VA status is not Completed');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Vendor Assignments'), 'Error should mention Vendor Assignments');
        }
        Test.stopTest();
    }
}