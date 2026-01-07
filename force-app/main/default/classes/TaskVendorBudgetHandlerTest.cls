@isTest
public class TaskVendorBudgetHandlerTest {

    @testSetup
    static void setupData() {
        // 1. Create Project
        Project__c proj = TestDataUtility.createProject('Budget Test Project');

        // 2. Create Vendor Assignment
        // We set a specific Vendor Percentage Cap (e.g., 50%) to test against.
        Vendor_Assignment__c va = TestDataUtility.createVendorAssignment(proj.Id);
        va.Budget_Percentage__c = 50.00; // Cap
        va.Vendor_Tasks_Remaining_Percentage__c = 50.00; // Initial state
        update va;
    }

    @isTest
    static void testValidationSuccess() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // 1. Insert Task 1 (20%) - Should pass (20 < 50)
        Task t1 = new Task(
            Subject = 'Task 1',
            Status = 'Not Started',
            WhatId = va.Id,
            Assigned_Percentage__c = 20
        );
        
        Test.startTest();
        // Manually invoke the handler since we don't have the actual Trigger code here.
        // In a real scenario, 'insert t1' would fire the trigger calling this method.
        TaskVendorBudgetHandler.validatePercentTotals(new List<Task>{t1}, null);
        insert t1; 
        
        // Simulate After Insert Trigger
        TaskVendorBudgetHandler.recalcRemainingFromTasks(new List<Task>{t1}, null);
        Test.stopTest();

        // Verify Remaining Percentage updated (50 - 20 = 30)
        Vendor_Assignment__c result = [SELECT Vendor_Tasks_Remaining_Percentage__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(30.00, result.Vendor_Tasks_Remaining_Percentage__c, 'Remaining percentage should be reduced');
    }

    @isTest
    static void testValidationFailureInsert() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // 1. Insert Task 1 (60%) - Should fail (60 > 50)
        Task t1 = new Task(
            Subject = 'Task Over Limit',
            Status = 'Not Started',
            WhatId = va.Id,
            Assigned_Percentage__c = 60
        );

        Test.startTest();
        try {
            // Simulate Trigger Validation
            TaskVendorBudgetHandler.validatePercentTotals(new List<Task>{t1}, null);
            
            // If the handler adds an error, DML usually fails in a real trigger context.
            // Since we are calling the handler directly on a list, we check if errors were added to the object instance.
            if (t1.getErrors().size() > 0) {
                throw new DmlException(t1.getErrors()[0].getMessage());
            }
            // Fallback if not verifying via addError directly
            insert t1;
            System.assert(false, 'Should have thrown exception due to budget overflow');
        } catch(Exception e) {
            System.assert(e.getMessage().contains('You can assign only'), 'Error message should explain the limit');
        }
        Test.stopTest();
    }

    @isTest
    static void testValidationFailureUpdate() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // 1. Insert valid task (40%)
        Task t1 = new Task(Subject = 'T1', WhatId = va.Id, Assigned_Percentage__c = 40);
        insert t1;
        
        // Update rollup manually to simulate state
        TaskVendorBudgetHandler.recalcRemainingFromTasks(new List<Task>{t1}, null);

        Test.startTest();
        // 2. Try to update task to 60% (Total would be 60 > 50)
        t1.Assigned_Percentage__c = 60;
        
        try {
            // Simulate Trigger Update Validation
            // Note: validatePercentTotals needs the NEW list.
            TaskVendorBudgetHandler.validatePercentTotals(new List<Task>{t1}, new Map<Id, Task>{t1.Id => t1});
            
            if (t1.getErrors().size() > 0) {
                throw new DmlException(t1.getErrors()[0].getMessage());
            }
            update t1;
            System.assert(false, 'Should have thrown exception on update');
        } catch(Exception e) {
            System.assert(e.getMessage().contains('You can assign only'), 'Error should allow update if limit exceeded');
        }
        Test.stopTest();
    }

    @isTest
    static void testRollupLogicDelete() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];

        // 1. Insert Task (20%)
        Task t1 = new Task(Subject = 'T1', WhatId = va.Id, Assigned_Percentage__c = 20);
        insert t1;
        TaskVendorBudgetHandler.recalcRemainingFromTasks(new List<Task>{t1}, null);

        // Verify state: 30% remaining
        Vendor_Assignment__c midResult = [SELECT Vendor_Tasks_Remaining_Percentage__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(30.00, midResult.Vendor_Tasks_Remaining_Percentage__c);

        Test.startTest();
        // 2. Delete Task
        delete t1;
        // Simulate Trigger After Delete
        TaskVendorBudgetHandler.recalcRemainingFromDeleted(new List<Task>{t1});
        Test.stopTest();

        // Verify state: Back to 50% remaining
        Vendor_Assignment__c endResult = [SELECT Vendor_Tasks_Remaining_Percentage__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(50.00, endResult.Vendor_Tasks_Remaining_Percentage__c, 'Deleting task should restore budget');
    }

    @isTest
    static void testBulkOperations() {
        Vendor_Assignment__c va = [SELECT Id FROM Vendor_Assignment__c LIMIT 1];
        
        // Insert 5 tasks of 10% each (Total 50%, exactly the limit)
        List<Task> tasks = new List<Task>();
        for(Integer i=0; i<5; i++) {
            tasks.add(new Task(
                Subject = 'Bulk Task ' + i,
                WhatId = va.Id,
                Assigned_Percentage__c = 10
            ));
        }

        Test.startTest();
        TaskVendorBudgetHandler.validatePercentTotals(tasks, null);
        insert tasks;
        TaskVendorBudgetHandler.recalcRemainingFromTasks(tasks, null);
        Test.stopTest();

        Vendor_Assignment__c result = [SELECT Vendor_Tasks_Remaining_Percentage__c FROM Vendor_Assignment__c WHERE Id = :va.Id];
        System.assertEquals(0.00, result.Vendor_Tasks_Remaining_Percentage__c, 'Budget should be fully utilized');
    }
}