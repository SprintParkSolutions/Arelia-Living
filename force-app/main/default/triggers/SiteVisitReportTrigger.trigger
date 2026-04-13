/**
 * @trigger      SiteVisitReportTrigger
 * @object       Site_Visit_Report__c
 * @events       after insert, after update
 *
 * @description
 * Trigger entry point for Site Visit Report automation.
 * This trigger follows Salesforce & PMD best practices:
 *  - No business logic inside the trigger
 *  - All processing is delegated to a handler class
 *  - Bulk-safe: operates on Trigger.new and Trigger.oldMap
 *  - Explicit event checks for clarity and maintainability
 *
 * NOTE:
 * Any future logic must be added ONLY in SiteVisitReportHandler.
 * Do NOT place queries or DML directly in this trigger.
 */
trigger SiteVisitReportTrigger on Site_Visit_Report__c (after insert, after update) {

    // AFTER trigger context
    if (Trigger.isAfter) {

        /**
         * AFTER INSERT
         * Called when new Site_Visit_Report__c records are created.
         * Trigger.new contains all inserted records (bulk-safe).
         */
        if (Trigger.isInsert) {
            SiteVisitReportHandler.afterInsert(Trigger.new);
        }

        /**
         * AFTER UPDATE
         * Called when existing Site_Visit_Report__c records are updated.
         * Trigger.new    → new versions of records
         * Trigger.oldMap → previous versions of records
         */
        if (Trigger.isUpdate) {
            SiteVisitReportHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
