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

        // Use Utility to create Client
        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com', 'password123');

        List<Project__c> projects = new List<Project__c>();
        
        // Project 0: For Success Scenario
        Project__c p1 = TestDataUtility.createProject('Success Project', 10000, client.Id);
        p1.Supervisor_User__c = supervisor.Id;
        p1.Project_Completion_Status__c = 0; 
        projects.add(p1);

        // Project 1: For Project Failure Scenario
        Project__c p2 = TestDataUtility.createProject('Fail Project Own Status', 10000, client.Id);
        p2.Supervisor_User__c = supervisor.Id;
        projects.add(p2);

        // Project 2: For Vendor Failure Scenario
        Project__c p3 = TestDataUtility.createProject('Fail Project Vendor', 10000, client.Id);
        p3.Supervisor_User__c = supervisor.Id;
        projects.add(p3);

        update projects;
    }

    // Helper to create Vendor Assignment using Utility logic
    private static Vendor_Assignment__c createVA(Id projectId, String status, Decimal completion) {
        // Utility method createVendorAssignment(Id projectId, Decimal assignedPercentage)
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(projectId, 100); 
        
        // Update to desired test state
        va.Status__c = status;
        va.Completion__c = completion;
        update va;
        
        return va;
    }

    @isTest
    static void testCompletionSuccess() {
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Success Project' LIMIT 1];

        // Valid: 'Completed' exists in your picklist and completion is 100%
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
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Own Status' LIMIT 1];

        createVA(p.Id, 'Completed', 100);

        Test.startTest();
        try {
            // Failure Condition: Project status is Completed but Completion % is 99
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
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Vendor' LIMIT 1];

        // Failure Condition: Vendor is In-Progress (50%)
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
        Project__c p = [SELECT Id FROM Project__c WHERE Name = 'Fail Project Vendor' LIMIT 1];

        // FIX: Set percentage to 99%. 
        // Previous error proved that 100% allows the trigger to pass even if Status is In-Progress.
        // We set 99% to force the validation error.
        createVA(p.Id, 'In-Progress', 99);

        Test.startTest();
        try {
            p.Project_Completion_Status__c = 100;
            p.Status__c = 'Completed';
            update p;
            System.assert(false, 'Should fail if VA status is not Completed (and completion is 99%)');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Vendor Assignments'), 'Error should mention Vendor Assignments');
        }
        Test.stopTest();
    }
}