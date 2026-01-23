/**
 * @description Service class for Quotation approvals.
 * Run as "without sharing" to allow Guest Users to update records in System Mode.
 */
public without sharing class QuotationService {
    
    // --- PART A: CALLED BY INTERNAL USER ("SEND FOR APPROVAL" BUTTON) ---
    // We use WITH USER_MODE here to satisfy PMD and enforce security for the internal sender.
    
    @InvocableMethod(
        label='Send Quote Approval Email'
        description='Sends email with Payment Terms table and PDF'
    )
    public static void sendApprovalEmail(List<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) {
            return;
        }
        Id oppId = oppIds[0];

        // 1. Fetch Opportunity Basic Info (Secure)
        Opportunity opp = [
            SELECT Id, Name
            FROM Opportunity
            WHERE Id = :oppId
            WITH USER_MODE
            LIMIT 1
        ];

        // --- EMAIL LOGIC ---
        String labelValue = System.Label.Arelia_Living_Enrollment_Members;
        List<String> targetEmails = new List<String>();

        if (String.isNotBlank(labelValue)) {
            for (String email : labelValue.split(',')) {
                targetEmails.add(email.trim());
            }
        }
        
        if (targetEmails.isEmpty()) {
            System.debug('Error: No email addresses found in Custom Label');
            return;
        }

        // 2. Fetch Latest Quotation (Secure)
        List<Quotation__c> quotes = [
            SELECT Id, Name
            FROM Quotation__c
            WHERE Opportunity__c = :oppId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (quotes.isEmpty()) {
            return;
        }
        Quotation__c quote = quotes[0];

        // 3. Fetch Payment Terms (Secure)
        List<Payment_Term__c> terms = [
            SELECT Term_Label__c, Percentage__c
            FROM Payment_Term__c
            WHERE Opportunity__c = :oppId
            WITH USER_MODE
            ORDER BY Name ASC
        ];

        // Build Table HTML
        String tableHtml = '<table style="border: 1px solid #ccc; border-collapse: collapse; width: 100%; font-family: Arial, sans-serif;">';
        tableHtml += '<tr style="background-color: #f2f2f2;">' +
            '<th style="border: 1px solid #ccc; padding: 10px; text-align: left;">Term Label</th>' +
            '<th style="border: 1px solid #ccc; padding: 10px; text-align: left;">Percentage</th></tr>';

        for (Payment_Term__c term : terms) {
            tableHtml += '<tr>' +
                '<td style="border: 1px solid #ccc; padding: 8px;">' + term.Term_Label__c + '</td>' +
                '<td style="border: 1px solid #ccc; padding: 8px;">' + term.Percentage__c + '%</td>' +
                '</tr>';
        }
        tableHtml += '</table>';

        // 4. Load Template (Secure)
        EmailTemplate et = [
            SELECT HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = 'Quotation_Manager_Approval'
            WITH USER_MODE
            LIMIT 1
        ];

        String htmlBody = et.HtmlValue;
        htmlBody = htmlBody.replace('[OPPORTUNITY_NAME]', opp.Name);
        htmlBody = htmlBody.replace('[PAYMENT_TERMS_TABLE]', tableHtml);

        String siteBaseUrl = 'https://sprintpark--dev4.sandbox.my.site.com/AreliaLiving/s';
        String siteUrl = siteBaseUrl + '/approvalpage?id=' + quote.Id;
        htmlBody = htmlBody.replace('[APPROVAL_LINK_URL]', siteUrl);

        // 5. Build Email
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(targetEmails);
        mail.setSubject('Approval Request: ' + quote.Name);
        mail.setHtmlBody(htmlBody);
        
        Id owdId = getOWD();
        if (owdId != null) {
            mail.setOrgWideEmailAddressId(owdId);
        }

        // --- 6. ATTACH PDF FROM FILES (ContentDocumentLink -> ContentVersion) ---
        // Secure Query for Link
        List<ContentDocumentLink> docLinks = [
            SELECT ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :quote.Id 
            AND ContentDocument.FileType = 'PDF'
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC 
            LIMIT 1
        ];

        if (!docLinks.isEmpty()) {
            // Secure Query for File Data
            ContentVersion cv = [
                SELECT Title, FileExtension, VersionData 
                FROM ContentVersion 
                WHERE ContentDocumentId = :docLinks[0].ContentDocumentId 
                AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];

            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(cv.Title + '.' + cv.FileExtension);
            efa.setBody(cv.VersionData);
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ efa });
        }

        // 7. Send Email
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    // --- PART B: CALLED BY GUEST USER (PUBLIC SITE) ---
    // We suppress PMD warnings here because Guest Users CANNOT pass 'WITH USER_MODE'
    // checks for these objects. We rely on the 'without sharing' class declaration.

    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void processRejection(Id quoteId, String reason) {
        if (quoteId == null) {
            System.debug('Error: Quote ID is null in processRejection');
            return;
        }

        // System Mode Query (Required for Guest User)
        Quotation__c q = [
            SELECT Id, Rejection_Reason__c 
            FROM Quotation__c 
            WHERE Id = :quoteId 
            LIMIT 1
        ];
        
        q.Rejection_Reason__c = reason;
        q.Manager_Approval__c = false;
        
        // System Mode Update (Required for Guest User)
        update q;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void processApproval(Id quoteId) {
        if (quoteId == null) {
            System.debug('Error: Quote ID is null in processApproval');
            return;
        }

        // System Mode Query (Required for Guest User)
        Quotation__c q = [
            SELECT Id, Manager_Approval__c 
            FROM Quotation__c 
            WHERE Id = :quoteId 
            LIMIT 1
        ];
        
        q.Manager_Approval__c = true;
        
        // System Mode Update (Required for Guest User)
        update q;
    }

    // Helper to get Org Wide Email Address (Secure)
    private static Id getOWD() {
        List<OrgWideEmailAddress> ow = [
            SELECT Id 
            FROM OrgWideEmailAddress 
            WHERE IsAllowAllProfiles = true 
            WITH USER_MODE
            LIMIT 1
        ];
        if (ow.isEmpty()) {
            return null;
        }
        return ow[0].Id;
    }
}