public class QuotationApprovalHandler {

    public static void handleAfterUpdate(
        List<Quotation__c> newList,
        Map<Id, Quotation__c> oldMap
    ) {
        List<Attachment> attachmentsToInsert = new List<Attachment>();
        Set<Id> approvedQuotationIds = new Set<Id>();

        // Detect approval change
        for (Quotation__c q : newList) {
            Quotation__c oldQ = oldMap.get(q.Id);

            if (
                oldQ != null &&
                oldQ.Manager_Approval__c == false &&
                q.Manager_Approval__c == true &&
                q.Opportunity__c != null
            ) {
                approvedQuotationIds.add(q.Id);
            }
        }

        if (approvedQuotationIds.isEmpty()) {
            return;
        }

        //  Fetch attachments in bulk
        Map<Id, List<Attachment>> quotationAttachmentsMap = new Map<Id, List<Attachment>>();

        for (Attachment a : [
            SELECT Id, Name, Body, ContentType, ParentId
            FROM Attachment
            WHERE ParentId IN :approvedQuotationIds
        ]) {
            if (!quotationAttachmentsMap.containsKey(a.ParentId)) {
                quotationAttachmentsMap.put(a.ParentId, new List<Attachment>());
            }
            quotationAttachmentsMap.get(a.ParentId).add(a);
        }

        // Clone attachments to Opportunity
        for (Quotation__c q : newList) {
            if (!approvedQuotationIds.contains(q.Id)) continue;

            List<Attachment> files = quotationAttachmentsMap.get(q.Id);
            if (files == null) continue;

            for (Attachment a : files) {
                attachmentsToInsert.add(new Attachment(
                    Name = a.Name,
                    Body = a.Body,
                    ContentType = a.ContentType,
                    ParentId = q.Opportunity__c
                ));
            }
        }

        // Insert attachments
        if (!attachmentsToInsert.isEmpty()) {
            insert attachmentsToInsert;
        }
    }
}