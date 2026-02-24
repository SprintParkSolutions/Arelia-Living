@SuppressWarnings('PMD.ApexCRUDViolation,PMD.CyclomaticComplexity,PMD.NPathComplexity')
public with sharing class InvoiceEmailHandler {

    public static void sendInvoiceEmailOnce(
        List<Invoice__c> newList,
        Map<Id, Invoice__c> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {
        if (newList == null || newList.isEmpty()) return;

        // 1) Collect candidate Invoice Ids (not sent yet)
        Set<Id> candidateInvoiceIds = new Set<Id>();
        for (Invoice__c inv : newList) {
            if (inv.Id == null) continue;

            // Already sent? skip
            if (inv.Invoice_Sent__c == true) continue;

            // Optional: if you want to send only when submitted, add condition here.
            // Example:
            // if (inv.Status__c != 'Submitted') continue;

            // On update, you can optionally require "something changed"
            // but user said: after insert and after update -> still send only once.
            candidateInvoiceIds.add(inv.Id);
        }
        if (candidateInvoiceIds.isEmpty()) return;

        // 2) Query invoices with Opportunity + Primary Contact
        List<Invoice__c> invoices = [
            SELECT Id, Name, Grand_Total__c, Invoice_Sent__c,
                   Opportunity__c,
                   Opportunity__r.Name,
                   Opportunity__r.Primary_Contact__c,
                   Opportunity__r.Primary_Contact__r.Name,
                   Opportunity__r.Primary_Contact__r.Email,Opportunity__r.Supervisor_User__c,
                   Opportunity__r.Supervisor_User__r.FirstName,
                   Opportunity__r.Supervisor_User__r.LastName,Opportunity__r.Supervisor_User__r.Email
            FROM Invoice__c
            WHERE Id IN :candidateInvoiceIds
        ];
        Map<Id, Invoice__c> invById = new Map<Id, Invoice__c>(invoices);

        // 3) Find linked files (Salesforce Files via ContentDocumentLink)
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :candidateInvoiceIds
        ];

        Map<Id, Set<Id>> docIdsByInvoice = new Map<Id, Set<Id>>();
        Set<Id> allDocIds = new Set<Id>();

        for (ContentDocumentLink l : links) {
            if (!docIdsByInvoice.containsKey(l.LinkedEntityId)) {
                docIdsByInvoice.put(l.LinkedEntityId, new Set<Id>());
            }
            docIdsByInvoice.get(l.LinkedEntityId).add(l.ContentDocumentId);
            allDocIds.add(l.ContentDocumentId);
        }

        // If no file at all for all candidates, stop
        if (allDocIds.isEmpty()) return;

        // 4) Latest versions for those documents
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE IsLatest = true
              AND ContentDocumentId IN :allDocIds
        ];

        Map<Id, ContentVersion> latestByDocId = new Map<Id, ContentVersion>();
        for (ContentVersion v : versions) {
            latestByDocId.put(v.ContentDocumentId, v);
        }

        // 5) Build emails + collect invoices to mark as sent
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Invoice__c> invoicesToMarkSent = new List<Invoice__c>();

        for (Id invId : invById.keySet()) {
            Invoice__c inv = invById.get(invId);

            // Must have primary contact email
            String toEmail = (inv.Opportunity__r != null && inv.Opportunity__r.Supervisor_User__r != null)
                ? inv.Opportunity__r.Supervisor_User__r.Email
                : null;

            if (String.isBlank(toEmail)) continue;

            // Must have at least 1 linked file
            Set<Id> docIds = docIdsByInvoice.get(invId);
            if (docIds == null || docIds.isEmpty()) continue;

            // Create attachments from files
            List<Messaging.EmailFileAttachment> fileAttachments = new List<Messaging.EmailFileAttachment>();
            Integer added = 0;

            for (Id docId : docIds) {
                if (added >= 10) break; // keep reasonable
                ContentVersion cv = latestByDocId.get(docId);
                if (cv == null || cv.VersionData == null) continue;

                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                String ext = String.isBlank(cv.FileExtension) ? '' : ('.' + cv.FileExtension);
                efa.setFileName(cv.Title + ext);
                efa.setBody(cv.VersionData);
                fileAttachments.add(efa);
                added++;
            }

            if (fileAttachments.isEmpty()) continue;

            String oppName = (inv.Opportunity__r != null) ? inv.Opportunity__r.Name : '';
            String supervisorName = inv.Opportunity__r.Supervisor_User__r.FirstName + ' ' + inv.Opportunity__r.Supervisor_User__r.LastName;
            // String contactName = (inv.Opportunity__r != null && inv.Opportunity__r.Primary_Contact__r != null)
            //     ? inv.Opportunity__r.Primary_Contact__r.Name
            //     : 'Customer';

            String totalText = (inv.Grand_Total__c == null) ? '0' : String.valueOf(inv.Grand_Total__c);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ toEmail });
            mail.setSubject('Invoice Created: ' + inv.Name + (String.isBlank(oppName) ? '' : (' | ' + oppName)));

            String htmlBody =
                '<p>Hi ' + escapeHtml(supervisorName) + ',</p>' +
                '<p>Your invoice <b>' + escapeHtml(inv.Name) + '</b>' +
                (String.isBlank(oppName) ? '' : (' for opportunity <b>' + escapeHtml(oppName) + '</b>')) +
                ' has been generated.</p>' +
                '<p><b>Grand Total:</b> ' + escapeHtml(totalText) + '</p>' +
                '<p>Please find the invoice attachment(s) in this email.</p>' +
                '<p>Thanks,<br/>Arelia Living</p>';

            mail.setHtmlBody(htmlBody);
            mail.setFileAttachments(fileAttachments);

            emails.add(mail);

            // Mark sent (do AFTER sendEmail)
            invoicesToMarkSent.add(new Invoice__c(
                Id = inv.Id,
                Invoice_Sent__c = true
            ));
        }

        if (emails.isEmpty()) return;

        // 6) Send
        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

        // 7) Mark sent only if send call succeeded
        // NOTE: sendEmail returns results in same order as emails list.
        // We'll mark all as sent if no exception thrown; optionally check each result success.
        List<Invoice__c> successUpdates = new List<Invoice__c>();
        Integer i = 0;
        for (Messaging.SendEmailResult r : results) {
            if (r != null && r.isSuccess()) {
                successUpdates.add(invoicesToMarkSent[i]);
            }
            i++;
        }

        if (!successUpdates.isEmpty()) {
            update successUpdates;
        }
    }

    private static String escapeHtml(String s) {
        if (s == null) return '';
        s = s.replace('&', '&amp;');
        s = s.replace('<', '&lt;');
        s = s.replace('>', '&gt;');
        s = s.replace('"', '&quot;');
        s = s.replace('\'', '&#39;');
        return s;
    }
}
