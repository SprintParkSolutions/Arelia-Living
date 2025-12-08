/**
 * @name        LeadTrigger
 * @description Handles logic after Lead creation and update:
 *              - On Insert: Send email to management if status is 'Pending'.
 *              - On Update: Send email to Lead if status becomes 'Approved'.
 *              - On Supervisor assignment change, call assignment handler.
 * @version     1.0
 */
trigger LeadTrigger on Lead (before insert, after insert, after update) {

    if (Trigger.isAfter && Trigger.isUpdate) {

        for (Lead leadRecord : Trigger.new) {
            Lead oldRecord = Trigger.oldMap.get(leadRecord.Id);

            // 🔹 Send both Lead + Management emails when status becomes Approved
            if (leadRecord.Approval_Status__c == 'Approved' &&
                oldRecord.Approval_Status__c != 'Approved' &&
                String.isNotBlank(leadRecord.Email)) 
            {
                LeadEmailHandler.sendEmailForLead(leadRecord);
            }

            // 🔹 Supervisor assignment logic (unchanged)
            if (String.isNotBlank(leadRecord.Supervisor_User__c) &&
                leadRecord.Supervisor_User__c != oldRecord.Supervisor_User__c) 
            {
                LeadAssignmentEmailHandler.handleSupervisorAssignment(
                    new List<Lead>{ leadRecord }, Trigger.oldMap
                );
            }
        }
    }
}
