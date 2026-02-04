trigger OpportunityCatalogueLinkTrigger on Opportunity (after insert) {
    List<Id> oppIds = new List<Id>();

    for (Opportunity opp : Trigger.new) {
        if (!String.isBlank(opp.Email__c)) {
            oppIds.add(opp.Id);
        }
    }

    if (!oppIds.isEmpty()) {
        OpportunityCatalogueEmailSender.sendCatalogueEmail(oppIds);
    }
}