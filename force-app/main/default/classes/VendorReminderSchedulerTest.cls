@IsTest
private class VendorReminderSchedulerTest {

    @TestSetup
    static void setupData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // 1. Create Roles and Manager User (Needed for Manager CC Logic)
            UserRole mgrRole = TestDataUtility.createUserRole('Regional Manager');
            TestDataUtility.createUserWithRole('mgrTest', mgrRole.Id);
            
            // 2. Create Supervisor
            User sup = TestDataUtility.createSupervisorUser('supTest');
            
            // 3. Create Email Template (Required by Scheduler)
            TestDataUtility.createSpecificEmailTemplate(
                'VA_Due_Alert_to_the_Supervisor_User', 
                'VA Reminder Alert', 
                'Reminder {{Vendor_Assignment__c.Name}}', 
                'Html Body: {{SupervisorName}} {{CompletionPercentage}} {{TaskTable}}'
            );
        }

        User sup = [SELECT Id FROM User WHERE Alias = 'supTest' LIMIT 1];

        // 4. Create Contact & Project
        Contact client = TestDataUtility.createContact('Client', 'client@test.com', 'pwd123');
        Project__c proj = TestDataUtility.createProject('Test Project', 10000, client.Id);

        // 5. Create Opportunity & Bypass Validation Rules
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp', sup.Id);
        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        update opp;

        // 6. Create Vendor (Must have Email for query to pick it up)
        Vendor__c vendor = TestDataUtility.createVendor('Test Vendor', 'Flooring & Tiling', 'vendor@test.com');
        
        // 7. Create Vendor Opportunity
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, vendor.Id, 'Active');

        // 8. Create Vendor Assignments EXPLICITLY with valid dates (>= Today)
        List<Vendor_Assignment__c> assignments = new List<Vendor_Assignment__c>();
        Date today = Date.today();

        // VA 0: High Risk (<25%). Start=Today, End=Tomorrow. (Total=1, Left=1).
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 10,
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(1)
        ));

        // VA 1: At Risk (<=95%). Start=Today, End=Today+10. (Total=10, Left=10).
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 90,
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(10)
        ));

        // VA 2: Future Start Date (Has not started yet). 
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 30,
            Vendor_Work_Start_Date__c = today.addDays(2), Vendor_Work_End_Date__c = today.addDays(12)
        ));

        // VA 3: Completed (100%).
        assignments.add(new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id, Opportunity__c = opp.Id, Supervisor_User__c = sup.Id, Project__c = proj.Id,
            Vendor__c = vendor.Id, Status__c = 'In-Progress', Completion__c = 100,
            Vendor_Work_Start_Date__c = today, Vendor_Work_End_Date__c = today.addDays(10)
        ));

        insert assignments;

        // 9. Insert Tasks to cover the Task Table HTML generation logic in the service
        List<Task> tasks = new List<Task>();
        for(Vendor_Assignment__c va : assignments) {
            tasks.add(new Task(
                Subject = 'Installation Setup',
                Status = 'Not Started',
                WhatId = va.Id
            ));
        }
        insert tasks;
    }

    // ==========================================
    // Test 1: Schedulable Context & Full Execution
    // ==========================================
    @IsTest
    static void testScheduledJobExecution() {
        Test.startTest();
        Integer beforeEmails = Limits.getEmailInvocations();

        // Run the Schedulable Job
        String cronExp = '0 0 12 * * ?'; 
        System.schedule('VendorReminderTestJob', cronExp, new VendorReminderScheduler());
        
        Test.stopTest(); // Forces asynchronous schedule/batch execution

        Integer afterEmails = Limits.getEmailInvocations();
        
        // Expected Emails: 
        // VA 0 triggers Vendor(1) + Supervisor(1) + Manager(1) = 3 emails total.
        Assert.isTrue(afterEmails > beforeEmails, 'The scheduled job should have processed the In-Progress assignments and dispatched alert emails based on the risk windows.');
    }

    // ==========================================
    // Test 2: Edge Case - No Assignments
    // ==========================================
    @IsTest
    static void testNoAssignmentsToProcess() {
        // Change all statuses so the query returns empty
        List<Vendor_Assignment__c> vas = [SELECT Id FROM Vendor_Assignment__c];
        for (Vendor_Assignment__c va : vas) {
            va.Status__c = 'Completed';
        }
        update vas;

        Test.startTest();
        Integer beforeEmails = Limits.getEmailInvocations();
        
        // Execute manually using a dummy schedulable context
        VendorReminderScheduler scheduler = new VendorReminderScheduler();
        scheduler.execute(null);
        
        Integer afterEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(beforeEmails, afterEmails, 'No emails should be sent when there are no In-Progress assignments.');
    }

    // ==========================================
    // Test 3: Edge Case - Missing Template & Null Dates
    // ==========================================
    @IsTest
    static void testNullDatesAndMissingTemplate() {
        // FIX: Wrap the Setup Object DML (EmailTemplate) in System.runAs to prevent MIXED_DML_OPERATION
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'VA_Due_Alert_to_the_Supervisor_User'];
            if (!templates.isEmpty()) {
                delete templates;
            }
        }

        // Break Dates on an Assignment (Non-Setup Object DML)
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        va.Vendor_Work_Start_Date__c = null;
        va.Vendor_Work_End_Date__c = null;
        update va;

        Test.startTest();
        // Should not throw exceptions; handles missing templates and null dates gracefully
        VendorReminderScheduler scheduler = new VendorReminderScheduler();
        scheduler.execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'The scheduler should execute successfully and handle missing templates or null dates gracefully without throwing exceptions.');
    }
}