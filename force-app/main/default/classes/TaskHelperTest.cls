@isTest
public class TaskHelperTest {

    @testSetup
    static void setupData() {
        // 1. Create Project using Utility
        Project__c proj = TestDataUtility.createProject('Test Project TaskCalc');

        // 2. Create Vendor Assignment using Utility
        // The utility sets the Project linkage automatically
        TestDataUtility.createVendorAssignment(proj.Id);
    }

    @isTest
    static void testPartialCompletion() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // Create 2 Tasks: 1 Completed, 1 Not Started
        List<Task> tasks = new List<Task>();
        tasks.add(new Task(
            Subject = 'Task 1',
            Status = 'Completed',
            WhatId = va.Id,
            ActivityDate = Date.today()
        ));
        tasks.add(new Task(
            Subject = 'Task 2',
            Status = 'Not Started', 
            WhatId = va.Id,
            ActivityDate = Date.today()
        ));
        insert tasks;

        Test.startTest();
        // Manually call the helper
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: 1 out of 2 tasks completed = 50%
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(50.00, result.Completion__c, 'Completion should be 50%');
    }

    @isTest
    static void testFullCompletion() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // Create 2 Tasks: Both Completed
        List<Task> tasks = new List<Task>();
        tasks.add(new Task(Subject = 'T1', Status = 'Completed', WhatId = va.Id));
        tasks.add(new Task(Subject = 'T2', Status = 'Completed', WhatId = va.Id));
        insert tasks;

        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: 2 out of 2 completed = 100%
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(100.00, result.Completion__c, 'Completion should be 100%');
    }

    @isTest
    static void testNoCompletion() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // Create 2 Tasks: None Completed
        List<Task> tasks = new List<Task>();
        tasks.add(new Task(Subject = 'T1', Status = 'In Progress', WhatId = va.Id));
        tasks.add(new Task(Subject = 'T2', Status = 'Not Started', WhatId = va.Id));
        insert tasks;

        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: 0 completed = 0%
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(0.00, result.Completion__c, 'Completion should be 0%');
    }

    @isTest
    static void testNoTasks() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // No tasks inserted

        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>{va.Id});
        Test.stopTest();

        // Verify: No tasks handled gracefully (remains 0 or calculates to 0)
        Vendor_Assignment__c result = [SELECT Completion__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        
        // Logic sets percentage = 0 if totalTasks is null/0
        System.assertEquals(0.00, result.Completion__c, 'Completion should be 0% when no tasks exist');
    }
    
    @isTest
    static void testEmptyInput() {
        // Verify guard clause (passing empty set)
        Test.startTest();
        TaskHelper.updateCompletionForAssignments(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Should exit gracefully without errors');
    }
}