trigger QuotationApprovalTrigger on Quotation__c (after update) {

    List<Attachment> toInsert = new List<Attachment>();

    for (Quotation__c q : Trigger.new) {
        Quotation__c oldQ = Trigger.oldMap.get(q.Id);

        if (!oldQ.Manager_Approval__c && q.Manager_Approval__c) {

            List<Attachment> files = [
                SELECT Id, Name, Body, ContentType
                FROM Attachment
                WHERE ParentId = :q.Id
            ];

            for (Attachment a : files) {
                toInsert.add(new Attachment(
                    Name = a.Name,
                    Body = a.Body,
                    ContentType = a.ContentType,
                    ParentId = q.Opportunity__c
                ));
            }
        }
    }

    if (!toInsert.isEmpty()) {
        insert toInsert;
    }
}