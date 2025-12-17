trigger CreateProjectFromOpportunity on Opportunity (after update) {
    CreateProjectFromOpportunityHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}