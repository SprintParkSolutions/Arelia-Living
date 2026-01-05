@isTest
public class TaskBulkControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('tasktest');

        // 2. Create Opportunity (to link tasks to)
        TestDataUtility.createOpportunity('Task Bulk Opp', u.Id);
    }

    @isTest
    static void testCreateTasksSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Prepare a list of tasks (in memory, not inserted)
        List<Task> tasksToInsert = new List<Task>();
        
        for(Integer i=0; i<5; i++) {
            Task t = new Task(
                Subject = 'Test Task ' + i,
                Status = 'Not Started',
                Priority = 'Normal',
                WhatId = opp.Id,
                ActivityDate = Date.today().addDays(i)
            );
            tasksToInsert.add(t);
        }

        Test.startTest();
        TaskBulkController.createTasks(tasksToInsert);
        Test.stopTest();

        // Verify insertion
        List<Task> insertedTasks = [SELECT Id FROM Task WHERE WhatId = :opp.Id];
        Assert.areEqual(5, insertedTasks.size(), 'Should have inserted 5 tasks');
    }

    @isTest
    static void testCreateTasksEmptyList() {
        Test.startTest();
        // Passing empty list should do nothing and not throw errors
        TaskBulkController.createTasks(new List<Task>());
        Test.stopTest();
        
        List<Task> allTasks = [SELECT Id FROM Task];
        Assert.areEqual(0, allTasks.size(), 'No tasks should be created');
    }

    @isTest
    static void testCreateTasksException() {
        Test.startTest();
        try {
            // Passing NULL will cause a NullPointerException at "newTasks.isEmpty()"
            // The controller's try/catch block should catch this and throw AuraHandledException
            TaskBulkController.createTasks(null);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught and handled');
            Assert.isTrue(e.getMessage().contains('Script-thrown exception'), 'Message should indicate handled error');
        }
        Test.stopTest();
    }
}