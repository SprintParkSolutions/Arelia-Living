trigger ArchitectureDesignTrigger on Architecture_Design__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        ArchitectureDesignTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
