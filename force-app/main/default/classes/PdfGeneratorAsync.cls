public class PdfGeneratorAsync implements Queueable {

    private Id oppId;
    private Id attachmentId;

    public PdfGeneratorAsync(Id opportunityId, Id attachmentId) {
        this.oppId = opportunityId;
        this.attachmentId = attachmentId;
    }

    public void execute(QueueableContext context) {

        /* ===============================
           FETCH OPPORTUNITY          
        =============================== */
        Opportunity opp = [
            SELECT Id,
                   Lead_Name__c,
                   Email__c,
                   Lead_Phone__c,
                   Supervisor_User__c, 
            Supervisor_User__r.Name,
                   Supervisor_User_Email__c
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        /* ===============================
           FETCH ATTACHMENT (PDF)
        =============================== */
        Attachment att = [
            SELECT Id, Name, Body
            FROM Attachment
            WHERE Id = :attachmentId
            LIMIT 1
        ];

        /* ===============================
           EMAIL TO LEAD
        =============================== */
        sendEmailUsingTemplate(
            'Opportunity_Catalogue_Quotation_Lead',
            opp.Email__c,
            opp,
            att
        );

        /* ===============================
           EMAIL TO SUPERVISOR (OPTIONAL)
           🔹 Kept commented as per your logic
        =============================== */
        
        if (!String.isBlank(opp.Supervisor_User_Email__c)) {
            sendEmailUsingTemplate(
                'Opportunity_Catalogue_Quotation_Supervisor',
                opp.Supervisor_User_Email__c,
                opp,
                att
            );
        }
        
    }

    /* =========================================================
       TEMPLATE EMAIL SENDER
    ========================================================= */
    private static void sendEmailUsingTemplate(
        String developerName,
        String toEmail,
        Opportunity opp,
        Attachment att
    ) {
        if (String.isBlank(toEmail)) return;

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        String htmlBody = tpl.HtmlValue
            .replace('{{{CustomerName}}}', opp.Lead_Name__c != null ? opp.Lead_Name__c : '')
            .replace('{{{CustomerEmail}}}', opp.Email__c != null ? opp.Email__c : '')
            .replace('{{{CustomerPhone}}}', opp.Lead_Phone__c != null ? opp.Lead_Phone__c : '')
            .replace('{{{SupervisorName}}}',
                opp.Supervisor_User__c != null ? String.valueOf(opp.Supervisor_User__r.Name) : '');

        String subject = tpl.Subject
            .replace('{{{CustomerName}}}', opp.Lead_Name__c != null ? opp.Lead_Name__c : '')
            .replace('{{{SupervisorName}}}',
                opp.Supervisor_User__c != null ? String.valueOf(opp.Supervisor_User__r.Name) : '');


        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
        efa.setBody(att.Body);
        efa.setFileName(att.Name);
        efa.setContentType('application/pdf');

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toEmail });
        msg.setSubject(subject);
        msg.setHtmlBody(htmlBody);
        msg.setFileAttachments(new Messaging.EmailFileAttachment[]{ efa });

        Id owdId = OpportunityQuotePDFController.getOWD();
        if (owdId != null) {
            msg.setOrgWideEmailAddressId(owdId);
        }

        msg.setWhatId(opp.Id);
        msg.setSaveAsActivity(true);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ msg });
    }
}