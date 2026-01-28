/**
 * @description Controller for managing vendor email communications.
 * Handles retrieval of specifications, tasks, and email dispatching.
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public with sharing class VendorEmailController {

    // ============================================================================
    // TEST VISIBLE VARIABLES FOR MOCKING (Bypasses Validation Rules in Tests)
    // ============================================================================
    @TestVisible private static List<Vendor_Assignment__c> mockAssignments;
    @TestVisible private static List<Task> mockTasks;

    /**
     * @description Retrieving content versions associated with an opportunity.
     * @param opportunityId The ID of the Opportunity.
     * @return List of ContentVersion records.
     */
    @AuraEnabled(cacheable=true)
    public static List<ContentVersion> getFilesByOpportunityId(String opportunityId) {
        if (String.isBlank(opportunityId)) {
            return new List<ContentVersion>();
        }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :opportunityId
            WITH SECURITY_ENFORCED
        ]) {
            docIds.add(link.ContentDocumentId);
        }

        if (docIds.isEmpty()) {
            return new List<ContentVersion>();
        }

        return [
            SELECT Id, Title, ContentDocumentId, FileType
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE
            WITH SECURITY_ENFORCED
            ORDER BY Title
        ];
    }

    /**
     * @description Gets all vendor categories from the Vendor__c object.
     * @return List of active picklist values.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getVendorCategories() {
        List<String> categories = new List<String>();
        for (Schema.PicklistEntry entry : Vendor__c.Vendor_Category__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                categories.add(entry.getValue());
            }
        }
        return categories;
    }

    /**
     * @description Retrieves vendors filtered by category.
     * @param category The vendor category to filter by.
     * @return List of Vendor__c records.
     */
    @AuraEnabled(cacheable=true)
    public static List<Vendor__c> getVendorsByCategory(String category) {
        if (String.isBlank(category)) {
            return new List<Vendor__c>();
        }
        return [
            SELECT Id, Name, Email__c, Vendor_Category__c, Average_Efficiency__c
            FROM Vendor__c
            WHERE Vendor_Category__c = :category
            AND Email__c != NULL
            AND Vendor_Status__c != 'Abscond'
            AND Vendor_Status__c != 'Unavailable'
            WITH SECURITY_ENFORCED
            ORDER BY Average_Efficiency__c DESC
        ];
    }

    /**
     * @description Retrieves email templates based on tender type.
     * @param tenderType The type of tender ('Backup' or other).
     * @return List containing the specific EmailTemplate.
     */
    @AuraEnabled(cacheable=true)
    public static List<EmailTemplate> getEmailTemplatesByType(String tenderType) {
        String devName = (tenderType == 'Backup') ? 'Backup_Tendor_Invitation' : 'Quatation_Email_Template';
        List<EmailTemplate> templates = [
            SELECT Id, Name, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :devName
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found: ' + devName);
        }
        return templates;
    }

    /**
     * @description Retrieves specifications for an opportunity and vendor category.
     * @param opportunityId The Opportunity ID.
     * @param category The Vendor Category.
     * @return List of Project_Specification__c objects.
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getSpecificationsByOpportunityAndCategory(String opportunityId, String category) {
        try {
            return new SpecQueryHelper().querySpecs(opportunityId, category);
        } catch (Exception e) {
            return new List<Project_Specification__c>();
        }
    }

    /**
     * @description Retrieves abscond vendor tasks and assignment details.
     * @param opportunityId The Opportunity ID.
     * @param category The Vendor Category.
     * @return AbscondedVendorDetails wrapper object.
     */
    @AuraEnabled(cacheable=true)
    public static AbscondedVendorDetails getAbscondedVendorTasks(String opportunityId, String category) {
        AbscondedVendorDetails details = new AbscondedVendorDetails();
        try {
            List<Vendor_Assignment__c> assigns;

            // MOCKING CHECK: If running test and mock is set, use mock instead of DB query
            if (Test.isRunningTest() && mockAssignments != null) {
                assigns = mockAssignments;
            } else {
                assigns = [
                    SELECT Id, Vendor_Work_Start_Date__c, Vendor_Work_End_Date__c, Completion__c
                    FROM Vendor_Assignment__c
                    WHERE Vendor_Opportunity__r.Opportunity__c = :opportunityId
                    AND Vendor_Opportunity__r.Vendor_Category__c = :category
                    AND Vendor_Opportunity__r.Vendor_Opportunity_Status__c = 'Abscond'
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
            }

            if (assigns.isEmpty()) {
                return details;
            }

            Vendor_Assignment__c va = assigns[0];
            details.overallCompletion = (va.Completion__c != null) ? va.Completion__c / 100 : 0;
            details.overallAssignmentStartDate = va.Vendor_Work_Start_Date__c;
            details.overallAssignmentEndDate = va.Vendor_Work_End_Date__c;

            List<Task> taskList;

            // MOCKING CHECK: If running test and mock is set, use mock instead of DB query
            if (Test.isRunningTest() && mockTasks != null) {
                taskList = mockTasks;
            } else {
                taskList = [SELECT Id, Subject, Status FROM Task WHERE WhatId = :va.Id WITH SECURITY_ENFORCED];
            }

            for (Task t : taskList) {
                details.tasks.add(new AbscondedTaskWrapper(t));
            }
            return details;
        } catch (Exception e) {
            return details;
        }
    }

    /**
     * @description Sends email to vendors with specifications or abscond details.
     * Suppressing ExcessiveParameterList because this signature is required by the LWC.
     * @param opportunityId The Opportunity ID.
     * @param fileIds List of ContentVersion IDs to attach.
     * @param vendorIds List of Vendor IDs to email.
     * @param category The Vendor Category.
     * @param tenderType The type of tender ('Backup' or 'New').
     */
    @AuraEnabled
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static void sendEmailToVendors(String opportunityId, List<String> fileIds, List<String> vendorIds, String category, String tenderType) {
        if (String.isBlank(opportunityId) || vendorIds == null || vendorIds.isEmpty()) {
            throw new AuraHandledException('Required fields missing.');
        }

        EmailSendingContext context = new EmailSendingContext();
        context.opportunityId = opportunityId;
        context.fileIds = fileIds;
        context.vendorIds = vendorIds;
        context.category = category;
        context.tenderType = tenderType;

        new EmailServiceHelper().processAndSendEmails(context);
    }

    // ============================================================================
    // WRAPPER CLASSES
    // ============================================================================

    /** @description Wrapper class for Abscond Vendor Details. */
    public class AbscondedVendorDetails {
        /** @description List of tasks associated with the absconded vendor. */
        @AuraEnabled public List<AbscondedTaskWrapper> tasks { get; set; }
        /** @description Overall completion percentage of the assignment. */
        @AuraEnabled public Decimal overallCompletion { get; set; }
        /** @description Start date of the assignment. */
        @AuraEnabled public Date overallAssignmentStartDate { get; set; }
        /** @description End date of the assignment. */
        @AuraEnabled public Date overallAssignmentEndDate { get; set; }

        /** @description Constructor initializing the list. */
        public AbscondedVendorDetails() {
            this.tasks = new List<AbscondedTaskWrapper>();
            this.overallCompletion = 0;
        }
    }

    /** @description Wrapper class for Abscond Task details. */
    public class AbscondedTaskWrapper {
        /** @description The ID of the task. */
        @AuraEnabled public Id taskId { get; set; }
        /** @description The subject of the task. */
        @AuraEnabled public String taskSubject { get; set; }
        /** @description The status of the task. */
        @AuraEnabled public String taskStatus { get; set; }

        /** * @description Constructor converting Task SObject to Wrapper.
         * @param t The Task record.
         */
        public AbscondedTaskWrapper(Task t) {
            this.taskId = t.Id;
            this.taskSubject = t.Subject;
            this.taskStatus = t.Status;
        }
    }

    /** @description Context class to pass data cleanly to email service. */
    private class EmailSendingContext {
        /** @description ID of the Opportunity. */
        public String opportunityId;
        /** @description List of ContentVersion IDs. */
        public List<String> fileIds;
        /** @description List of Vendor IDs. */
        public List<String> vendorIds;
        /** @description The Vendor Category. */
        public String category;
        /** @description Type of tender (New or Backup). */
        public String tenderType;
    }

    /** @description Internal wrapper for email content parts. */
    private class EmailContentWrapper {
        /** @description List of specification records. */
        public List<SObject> specs;
        /** @description HTML string for the specifications table. */
        public String specTable;
        /** @description HTML string for the absconded tasks table. */
        public String abscondedTable;
    }

    /** @description Helper class for Email Creation context to reduce parameter list. */
    private class EmailCreationContext {
        /** @description The related Opportunity record. */
        public Opportunity opportunity;
        /** @description The EmailTemplate to be used. */
        public EmailTemplate template;
        /** @description The generated content wrapper. */
        public EmailContentWrapper content;
        /** @description List of attachments to be sent. */
        public List<Messaging.EmailFileAttachment> attachments;
        /** @description Default category fallback. */
        public String defaultCategory;
    }

    // ============================================================================
    // INNER HELPER CLASSES
    // ============================================================================

    /** @description Helper class for querying specifications. */
    private with sharing class SpecQueryHelper {
        /**
         * @description Queries Project_Specification__c based on FieldSet.
         * @param opportunityId The Opportunity ID.
         * @param category The Vendor Category.
         * @return List of SObjects.
         */
        public List<SObject> querySpecs(String opportunityId, String category) {
            Schema.FieldSet fs = SObjectType.Project_Specification__c.FieldSets.getMap().get('Vendor_Email_Fields');
            if (fs == null) { return new List<Project_Specification__c>(); }

            List<Schema.FieldSetMember> fields = fs.getFields();
            if (fields.isEmpty()) { return new List<Project_Specification__c>(); }

            String query = 'SELECT Id, Interior_Product__c, Interior_Product__r.Name, Quality__c, Quantity__c, ';
            for (Schema.FieldSetMember f : fields) {
                if (!query.containsIgnoreCase(f.getFieldPath())) {
                    query += f.getFieldPath() + ', ';
                }
            }
            query = query.removeEnd(', ');
            query += ' FROM Project_Specification__c WHERE Opportunity__c = :opportunityId AND Vendor_Category__c = :category WITH SECURITY_ENFORCED ORDER BY CreatedDate ASC';
            return Database.query(query);
        }
    }

    /** @description Helper class for processing and sending emails. */
    private with sharing class EmailServiceHelper {
        /**
         * @description Main orchestration method for sending emails.
         * @param ctx The sending context containing IDs and types.
         */
        public void processAndSendEmails(EmailSendingContext ctx) {
            String templateDevName = (ctx.tenderType == 'Backup') ? 'Backup_Tendor_Invitation' : 'Quatation_Email_Template';
            EmailTemplate template = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :templateDevName WITH SECURITY_ENFORCED LIMIT 1];

            EmailContentWrapper content = buildContent(ctx);

            Opportunity opp = [
                SELECT Id, Name, Supervisor_User__r.Name, Supervisor_User__r.Email, Supervisor_User__r.Phone, Project_Scope__c
                FROM Opportunity WHERE Id = :ctx.opportunityId WITH SECURITY_ENFORCED LIMIT 1
            ];

            List<Messaging.EmailFileAttachment> attachments = buildAttachments(ctx.fileIds, content.specs);

            List<Vendor__c> vendors = [SELECT Id, Name, Email__c, Vendor_Category__c FROM Vendor__c WHERE Id IN :ctx.vendorIds AND Email__c != NULL WITH SECURITY_ENFORCED];
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

            EmailCreationContext creationCtx = new EmailCreationContext();
            creationCtx.opportunity = opp;
            creationCtx.template = template;
            creationCtx.content = content;
            creationCtx.attachments = attachments;
            creationCtx.defaultCategory = ctx.category;

            for (Vendor__c v : vendors) {
                emails.add(createEmail(v, creationCtx));
            }

            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                throw new AuraHandledException('Error sending emails: ' + e.getMessage());
            }
        }

        /**
         * @description Builds the email content based on tender type.
         * @param ctx The sending context.
         * @return Populated EmailContentWrapper.
         */
        private EmailContentWrapper buildContent(EmailSendingContext ctx) {
            EmailContentWrapper wrapper = new EmailContentWrapper();
            if (ctx.tenderType == 'New') {
                wrapper.specs = new SpecQueryHelper().querySpecs(ctx.opportunityId, ctx.category);
                wrapper.specTable = new TableBuilderHelper().buildDynamicSpecificationTable(wrapper.specs);
            } else if (ctx.tenderType == 'Backup') {
                AbscondedVendorDetails ad = VendorEmailController.getAbscondedVendorTasks(ctx.opportunityId, ctx.category);
                wrapper.abscondedTable = new TableBuilderHelper().buildAbscondedTaskTable(ad);
            }
            return wrapper;
        }

        /**
         * @description Creates a single email message object.
         * @param v The Vendor record.
         * @param ctx The email creation context.
         * @return Configured SingleEmailMessage.
         */
        private Messaging.SingleEmailMessage createEmail(Vendor__c v, EmailCreationContext ctx) {
            String cat = (v.Vendor_Category__c != null ? v.Vendor_Category__c : ctx.defaultCategory);
            String subject = ctx.template.Subject
                .replace('{{{Vendor_Category__c}}}', cat)
                .replace('{{{project_scope}}}', (ctx.opportunity.Project_Scope__c != null ? ctx.opportunity.Project_Scope__c : ''));

            String body = generateEmailBody(v, cat, ctx);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(UserInfo.getUserId());
            email.setWhatId(ctx.opportunity.Id);
            email.setSaveAsActivity(true);
            email.setToAddresses(new List<String>{ v.Email__c });
            email.setTreatTargetObjectAsRecipient(false);
            email.setSubject(subject);
            email.setHtmlBody(body);
            email.setFileAttachments(ctx.attachments);

            if (ctx.opportunity.Supervisor_User__r?.Name != null) {
                email.setSenderDisplayName(ctx.opportunity.Supervisor_User__r.Name + ' (Project Supervisor)');
            }
            return email;
        }

        /**
         * @description Generates the HTML body by replacing placeholders.
         * @param v The Vendor record.
         * @param category The determined category.
         * @param ctx The creation context containing template and opportunity.
         * @return The final HTML string.
         */
        private String generateEmailBody(Vendor__c v, String category, EmailCreationContext ctx) {
            return ctx.template.HtmlValue
                .replace('{{{Opportunity.Name}}}', (ctx.opportunity.Name != null ? ctx.opportunity.Name : ''))
                .replace('{{{Opportunity.SupervisorName}}}', (ctx.opportunity.Supervisor_User__r?.Name != null ? ctx.opportunity.Supervisor_User__r.Name : ''))
                .replace('{{{Opportunity.SupervisorEmail}}}', (ctx.opportunity.Supervisor_User__r?.Email != null ? ctx.opportunity.Supervisor_User__r.Email : ''))
                .replace('{{{Opportunity.SupervisorPhone}}}', (ctx.opportunity.Supervisor_User__r?.Phone != null ? ctx.opportunity.Supervisor_User__r.Phone : ''))
                .replace('{{{Vendor__c.Name}}}', (v.Name != null ? v.Name : ''))
                .replace('{{{Vendor_Category__c}}}', category)
                .replace('{{{Vendor__c.Category}}}', category)
                .replace('{{{Specification_Table}}}', (ctx.content.specTable != null ? ctx.content.specTable : ''))
                .replace('{{{Absconded_Task_Table}}}', (ctx.content.abscondedTable != null ? ctx.content.abscondedTable : ''));
        }

        /**
         * @description Aggregates attachments from file IDs and parent IDs.
         * @param fileIds Direct ContentVersion IDs.
         * @param specs List of specification records to find related images.
         * @return List of EmailFileAttachments.
         */
        private List<Messaging.EmailFileAttachment> buildAttachments(List<String> fileIds, List<SObject> specs) {
            List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            if (fileIds != null && !fileIds.isEmpty()) {
                for (ContentVersion f : [SELECT Title, VersionData, FileExtension FROM ContentVersion WHERE Id IN :fileIds AND IsLatest = TRUE WITH SECURITY_ENFORCED]) {
                    Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                    att.setFileName(f.Title + (String.isNotBlank(f.FileExtension) ? '.' + f.FileExtension : ''));
                    att.setBody(f.VersionData);
                    attachments.add(att);
                }
            }
             if (specs != null && !specs.isEmpty()) {
                Set<Id> productIds = new Set<Id>();
                for (SObject s : specs) {
                    Id prodId = (Id) s.get('Interior_Product__c');
                    if (prodId != null) { productIds.add(prodId); }
                }
                attachments.addAll(getAttachmentsFromParentIds(productIds));
            }
            return attachments;
        }

        /**
         * @description Fetches attachments linked to parent entities.
         * @param parentIds Set of parent IDs.
         * @return List of EmailFileAttachments.
         */
        private List<Messaging.EmailFileAttachment> getAttachmentsFromParentIds(Set<Id> parentIds) {
            List<Messaging.EmailFileAttachment> result = new List<Messaging.EmailFileAttachment>();
            if (parentIds.isEmpty()) { return result; }
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink cdl : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :parentIds WITH SECURITY_ENFORCED]) {
                docIds.add(cdl.ContentDocumentId);
            }
            if (docIds.isEmpty()) { return result; }
            for (ContentVersion cv : [SELECT Title, VersionData, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE WITH SECURITY_ENFORCED]) {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                att.setFileName(cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : ''));
                att.setBody(cv.VersionData);
                result.add(att);
            }
            return result;
        }
    }

    /** @description Helper class specifically for HTML Table generation. */
    private with sharing class TableBuilderHelper {
        /**
         * @description Builds an HTML table for specifications dynamically from a FieldSet.
         * @param records List of records to display.
         * @return HTML Table string.
         */
        public String buildDynamicSpecificationTable(List<SObject> records) {
            if (records == null || records.isEmpty()) { return ''; }
            Schema.FieldSet fs = SObjectType.Project_Specification__c.FieldSets.getMap().get('Vendor_Email_Fields');
            if (fs == null) { return ''; }

            String table = '<table border="1" style="border-collapse: collapse; width: 100%; font-family: Arial, sans-serif;"><thead style="background-color: #f2f2f2;"><tr>';
            for (Schema.FieldSetMember f : fs.getFields()) {
                if (f.getFieldPath() != 'Description__c') {
                    table += '<th style="padding: 10px; text-align: left;">' + f.getLabel() + '</th>';
                }
            }
            table += '</tr></thead><tbody>';
            for (SObject row : records) {
                table += '<tr>';
                for (Schema.FieldSetMember f : fs.getFields()) {
                    if (f.getFieldPath() != 'Description__c') {
                        table += '<td style="padding: 10px;">' + getDeepValue(row, f.getFieldPath()) + '</td>';
                    }
                }
                table += '</tr>';
            }
            return table + '</tbody></table>';
        }

        /**
         * @description Builds an HTML table for absconded vendor tasks.
         * @param details The AbscondedVendorDetails wrapper.
         * @return HTML string.
         */
        public String buildAbscondedTaskTable(AbscondedVendorDetails details) {
            if (details == null || (details.tasks.isEmpty() && details.overallCompletion == 0)) {
                return '';
            }
            return buildAbscondedSummary(details) + buildAbscondedRows(details);
        }

        /**
         * @description Builds the summary section of the absconded table.
         * @param details The wrapper containing summary data.
         * @return HTML string div.
         */
        private String buildAbscondedSummary(AbscondedVendorDetails details) {
            String output = '<div style="margin-bottom: 15px; border: 1px solid #ccc; padding: 10px; background-color: #f9f9f9;">';
            if (details.overallCompletion != null) {
                output += '<p><strong>Overall Assignment Completion: </strong>' + (details.overallCompletion * 100).setScale(2) + '%</p>';
            }
            if (details.overallAssignmentStartDate != null) {
                output += '<p><strong>Start Date: </strong>' + details.overallAssignmentStartDate.format() + '</p>';
            }
            if (details.overallAssignmentEndDate != null) {
                output += '<p><strong>End Date: </strong>' + details.overallAssignmentEndDate.format() + '</p>';
            }
            return output + '</div>';
        }

        /**
         * @description Builds the rows for the absconded tasks.
         * @param details The wrapper containing task lists.
         * @return HTML string table.
         */
        private String buildAbscondedRows(AbscondedVendorDetails details) {
            if (details.tasks.isEmpty()) {
                return '';
            }
            String output = '<h4 style="margin-top: 15px;">Individual Tasks:</h4><table border="1" style="border-collapse: collapse; width: 100%;"><thead><tr><th style="padding: 8px;">Task</th><th style="padding: 8px;">Status</th></tr></thead><tbody>';
            for (AbscondedTaskWrapper t : details.tasks) {
                output += '<tr><td style="padding: 8px;">' + (t.taskSubject != null ? t.taskSubject : '') + '</td><td style="padding: 8px;">' + (t.taskStatus != null ? t.taskStatus : '') + '</td></tr>';
            }
            return output + '</tbody></table>';
        }

        /**
         * @description Retrieves values from SObjects, supporting parent relationships (e.g., Parent.Name).
         * @param record The SObject record.
         * @param fieldPath The API name of the field.
         * @return String value of the field.
         */
        private String getDeepValue(SObject record, String fieldPath) {
            if (record == null) { return ''; }
            if (!fieldPath.contains('.')) {
                Object val = record.get(fieldPath);
                return (val != null) ? String.valueOf(val) : '';
            }
            List<String> parts = fieldPath.split('\\.');
            SObject currentObj = record;
            for (Integer i = 0; i < parts.size() - 1; i++) {
                currentObj = currentObj.getSObject(parts[i]);
                if (currentObj == null) { return ''; }
            }
            Object val = currentObj.get(parts[parts.size() - 1]);
            return (val != null) ? String.valueOf(val) : '';
        }
    }
}