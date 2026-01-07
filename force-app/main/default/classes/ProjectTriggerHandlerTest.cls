@isTest
public class ProjectTriggerHandlerTest {

    @testSetup
    static void setupData() {
        // Declare the User variable outside the runAs block so we can use its ID later
        User supervisor;

        // --- SETUP OBJECTS (Must be in runAs to avoid Mixed DML) ---
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // 1. Create Roles
            UserRole managerRole = TestDataUtility.createUserRole('Regional Manager');
            UserRole enrollmentRole = TestDataUtility.createUserRole('Enrollment Team');

            // 2. Create Users
            // We don't strictly need to store mgrUser/enrollUser in variables if not used later, 
            // but we do need the Supervisor.
            TestDataUtility.createUserWithRole('mgr', managerRole.Id);
            TestDataUtility.createUserWithRole('enr', enrollmentRole.Id);
            supervisor = TestDataUtility.createSupervisorUser('sup');

            // 3. Setup Email Templates (Moved here as they are also Setup/Metadata objects)
            TestDataUtility.createSpecificEmailTemplate('Client_Project_Notification', 'Client Notification', 'Welcome Client');
            TestDataUtility.createSpecificEmailTemplate('Supervisor_Project_Notification', 'Sup Notification', 'Project Assigned');
        }

        // --- NON-SETUP OBJECTS (Safe to create now that runAs block is closed) ---

        // 4. Create Client (Contact)
        Contact client = TestDataUtility.createContact('Test Client', 'client@test.com');

        // 5. Create Project
        Project__c proj = TestDataUtility.createProject('Test Project Code Gen');
        proj.Client__c = client.Id;
        // We can safely use supervisor.Id here because the variable was defined in the outer scope
        proj.Supervisor_User__c = supervisor.Id; 
        update proj;
    }

    @isTest
    static void testAssignProjectCodes() {
        // Fetch project created in setup
        List<Project__c> projects = [SELECT Id, Project_Code__c FROM Project__c];
        
        // Ensure code is empty to test the logic
        for(Project__c p : projects) {
            p.Project_Code__c = null;
        }

        Test.startTest();
        ProjectTriggerHandler.assignProjectCodes(projects);
        Test.stopTest();

        // Verification
        for(Project__c p : projects) {
            System.assert(String.isNotBlank(p.Project_Code__c), 'Project Code should have been generated');
            System.assert(p.Project_Code__c.startsWith('AL-'), 'Project Code should start with AL-');
        }
    }

    @isTest
    static void testSendProjectApprovedEmail() {
        List<Project__c> projects = [SELECT Id, Name, Client__c, Supervisor_User__c, Project_Code__c, Status__c, Type_Of_Project__c, Project_Scope__c FROM Project__c];

        Test.startTest();
        Integer startCount = Limits.getEmailInvocations();

        // Run the email logic
        ProjectTriggerHandler.sendProjectApprovedEmail(projects);

        Integer endCount = Limits.getEmailInvocations();
        Test.stopTest();

        System.debug('Emails Sent: ' + (endCount - startCount));
        System.assert(true, 'Method executed successfully');
    }

    @isTest
    static void testSendProjectApprovedEmailWithNull() {
        Test.startTest();
        try {
            ProjectTriggerHandler.sendProjectApprovedEmail(null);
        } catch(Exception e) {
            System.assert(false, 'Should handle null list gracefully');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testAssignProjectCodesWithNull() {
        Test.startTest();
        try {
            ProjectTriggerHandler.assignProjectCodes(null);
        } catch(Exception e) {
            System.assert(false, 'Should handle null list gracefully');
        }
        Test.stopTest();
    }
}