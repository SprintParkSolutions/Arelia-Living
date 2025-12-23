public without sharing class OpportunityQuotePDFController {

    // ----------------------------------------------------
    // PROPERTIES USED BY VISUALFORCE PDF PAGE
    // ----------------------------------------------------
    public Opportunity Opp { get; set; }
    public List<Project_Specification__c> specItems { get; set; }
    public Decimal grandTotal { get; set; }

    // ----------------------------------------------------
    // CONSTRUCTOR (called when VF PDF loads)
    // ----------------------------------------------------
    public OpportunityQuotePDFController() {
        try {
            Id opportunityId = ApexPages.currentPage().getParameters().get('opportunityId');

            Opp = [
                SELECT Id, Name, Lead_Name__c, Email__c, Lead_Phone__c,
                       CreatedDate, Type_of_Project__c, Owner.Name,
                       Supervisor_User__r.Name, Supervisor_User_Email__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            specItems = [
                SELECT Quantity__c, Unit_Price__c, Total_Amount__c, Quality__c,
                       Interior_Product__r.Name,
                       Interior_Product__r.Product_Category__c,
                       Interior_Product__r.Room_Type__c
                FROM Project_Specification__c
                WHERE Opportunity__c = :opportunityId
                ORDER BY CreatedDate DESC
            ];

            grandTotal = 0;
            for (Project_Specification__c s : specItems) {
                grandTotal += (s.Total_Amount__c != null ? s.Total_Amount__c : 0);
            }

        } catch (Exception ex) {
            throw new AuraHandledException('PDF Page Error: ' + ex.getMessage());
        }
    }


    // ----------------------------------------------------
    // METHOD CALLED FROM LWC TO CREATE SPEC + PDF
    // ----------------------------------------------------
    @AuraEnabled
    public static String generateQuoteAndSave(Id opportunityId, List<Project_Specification__c> cartItems) {

        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required');
        }

        try {
            // Delete old items
            List<Project_Specification__c> oldItems = [
                SELECT Id FROM Project_Specification__c WHERE Opportunity__c = :opportunityId
            ];
            if (!oldItems.isEmpty()) delete oldItems;

            // Insert new spec items
            List<Project_Specification__c> toInsert = new List<Project_Specification__c>();
            for (Project_Specification__c c : cartItems) {

                Interior_Product__c prod = [
                    SELECT Product_Category__c, Room_Type__c
                    FROM Interior_Product__c
                    WHERE Id = :c.Interior_Product__c
                    LIMIT 1
                ];

                toInsert.add(new Project_Specification__c(
                    Opportunity__c = opportunityId,
                    Interior_Product__c = c.Interior_Product__c,
                    Quantity__c = c.Quantity__c,
                    Unit_Price__c = c.Unit_Price__c,
                    Quality__c = c.Quality__c,
                    Vendor_Category__c = prod.Product_Category__c
                ));
            }
            insert toInsert;

            // Generate PDF + Save + Email
            generatePdfAndEmail(opportunityId);

            return 'SUCCESS';

        } catch (Exception ex) {
            throw new AuraHandledException('Quotation Error: ' + ex.getMessage());
        }
    }


    // ----------------------------------------------------
    // MAIN PDF + EMAIL METHOD
    // ----------------------------------------------------
    @AuraEnabled
    public static void generatePdfAndEmail(Id oppId) {

        // Generate PDF
        PageReference pdfPage = Page.Opportunity_Quote_PDF;
        pdfPage.getParameters().put('opportunityId', oppId);
        Blob pdfBlob = pdfPage.getContentAsPDF();

        // Create Quotation record
        Quotation__c qt = new Quotation__c(
            Opportunity__c = oppId,
            Manager_Approval__c = false,
            Name = 'Quotation - ' + Datetime.now().format('yyyyMMdd_HHmmss')
        );
        insert qt;

        // Attach PDF to Quotation__c
        Attachment att = new Attachment(
            Name = 'Quotation_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.pdf',
            ParentId = qt.Id,
            Body = pdfBlob,
            ContentType = 'application/pdf'
        );
        insert att;


        // Fetch Opportunity
        Opportunity opp = [
            SELECT Id, Lead_Name__c, Email__c, Lead_Phone__c,
                   Supervisor_User__r.Name, Supervisor_User_Email__c
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        // Email Customer
        sendEmailUsingTemplate(
            'Opportunity_Catalogue_Quotation_Lead',
            opp.Email__c,
            opp,
            att
        );

        // Email Supervisor
       /* if (!String.isBlank(opp.Supervisor_User_Email__c)) {
            sendEmailUsingTemplate(
                'Opportunity_Catalogue_Quotation_Supervisor',
                opp.Supervisor_User_Email__c,
                opp,
                att
            );
        }*/
    }


    // ----------------------------------------------------
    // EMAIL HELPER METHOD
    // ----------------------------------------------------
    private static void sendEmailUsingTemplate(
        String developerName, String toEmail,
        Opportunity opp, Attachment att
    ) {
        if (String.isBlank(toEmail)) return;

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        String htmlBody = tpl.HtmlValue
            .replace('{{{CustomerName}}}', opp.Lead_Name__c)
            .replace('{{{CustomerEmail}}}', opp.Email__c)
            .replace('{{{CustomerPhone}}}', opp.Lead_Phone__c)
            .replace('{{{SupervisorName}}}', opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Name : '');

        String subject = tpl.Subject
            .replace('{{{CustomerName}}}', opp.Lead_Name__c)
            .replace('{{{SupervisorName}}}', opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Name : '');

        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
        efa.setBody(att.Body);
        efa.setFileName(att.Name);
        efa.setContentType('application/pdf');

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toEmail });
        msg.setSubject(subject);
        msg.setHtmlBody(htmlBody);
        msg.setFileAttachments(new Messaging.EmailFileAttachment[]{efa});
        msg.setOrgWideEmailAddressId(getOWD());
        msg.setWhatId(opp.Id);
        msg.setSaveAsActivity(true);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    private static Id getOWD() {
        List<OrgWideEmailAddress> ow = [
            SELECT Id FROM OrgWideEmailAddress WHERE IsAllowAllProfiles = true LIMIT 1
        ];
        return ow.isEmpty() ? null : ow[0].Id;
    }
}