public with sharing class TaskBulkController {
    @AuraEnabled
    public static void createTasks(List<Task> newTasks) {
        try {
            if (!newTasks.isEmpty()) {
                insert newTasks;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error creating tasks: ' + e.getMessage());
        }
    }
}