/**
 * @description Trigger handler for Architecture_Design__c Manager Approval Emails.
 * Handles detection of status changes and email dispatching.
 * * NOTE: This class is 'without sharing' to ensure system emails are sent even if the 
 * triggering user (e.g., Guest User) lacks direct access to User/Template objects.
 * PMD CRUD violations are suppressed for this reason.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ArchitectureDesignTriggerHandler {

    private static final String STATUS_APPROVED         = 'Approved';
    private static final String TEMPLATE_DEVELOPER_NAME = 'Architecture_Manager_Approval';

    /**
     * @description Inner class to hold email configuration context, reducing parameter count.
     */
    private class EmailContext {
        public Map<Id, Architecture_Design__c> designMap;
        public Map<Id, ContentVersion> fileMap;
        public EmailTemplate template;
        public List<String> toAddresses;
        public Id orgWideId;
        public String siteBase;
    }

    /**
     * @description Entry point from Trigger. Checks for status change to Approved.
     */
    public static void onAfterUpdate(List<Architecture_Design__c> newList, Map<Id, Architecture_Design__c> oldMap) {
        System.debug('--- Trigger Started: ArchitectureDesignTriggerHandler ---');
        
        List<Id> approvedDesignIds = new List<Id>();

        for (Architecture_Design__c newRec : newList) {
            Architecture_Design__c oldRec = oldMap.get(newRec.Id);
            // Detect status change to 'Approved'
            if (newRec.Status__c == STATUS_APPROVED && (oldRec == null || oldRec.Status__c != STATUS_APPROVED)) {
                approvedDesignIds.add(newRec.Id);
            }
        }

        if (!approvedDesignIds.isEmpty()) {
            sendEmailWithAttachment(approvedDesignIds);
        }
    }

    /**
     * @description Main orchestration method for sending emails.
     */
    private static void sendEmailWithAttachment(List<Id> designIds) {
        // 1. Prepare Email Context
        EmailContext ctx = new EmailContext();
        
        ctx.toAddresses = parseEmailsFromLabel(Label.Arelia_Living_Enrollment_Members);
        if (ctx.toAddresses.isEmpty()) {
            System.debug('ERROR: Label Arelia_Living_Enrollment_Members is empty.');
            return;
        }

        ctx.orgWideId = getDefaultOrgWideEmailAddressId();
        if (ctx.orgWideId == null) {
            System.debug('ERROR: Org-Wide Address not found or not accessible.');
            return;
        }

        ctx.template = getEmailTemplate();
        if (ctx.template == null) {
            System.debug('ERROR: Email Template "' + TEMPLATE_DEVELOPER_NAME + '" not found.');
            return;
        }

        ctx.siteBase = Label.Arelia_Site_Label;
        if (ctx.siteBase != null && ctx.siteBase.endsWith('/')) {
            ctx.siteBase = ctx.siteBase.removeEnd('/');
        }

        // 2. Query Data & Files
        ctx.designMap = queryDesignData(designIds);
        ctx.fileMap = mapDesignToLatestFile(designIds);

        // 3. Process Sending
        processAndSendEmails(designIds, ctx);
    }

    /**
     * @description Helper to query Design Data safely.
     * UPDATED: Now fetches FirstName and LastName explicitly to avoid Nicknames.
     */
    private static Map<Id, Architecture_Design__c> queryDesignData(List<Id> designIds) {
        return new Map<Id, Architecture_Design__c>([
            SELECT Id, 
                   Opportunity__c,
                   Opportunity__r.Lead_Name__c,
                   Opportunity__r.Email__c,
                   // FIX: Get explicit First and Last name
                   Opportunity__r.Supervisor_User__r.FirstName, 
                   Opportunity__r.Supervisor_User__r.LastName,
                   Opportunity__r.Supervisor_User__r.Email
            FROM Architecture_Design__c
            WHERE Id IN :designIds
        ]);
    }

    /**
     * @description Helper to map Design IDs to their latest ContentVersion file.
     */
    private static Map<Id, ContentVersion> mapDesignToLatestFile(List<Id> designIds) {
        Map<Id, Id> designIdToDocId = new Map<Id, Id>();
        Set<Id> docIds = new Set<Id>();

        for (ContentDocumentLink cdl : [SELECT LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :designIds]) {
            if (!designIdToDocId.containsKey(cdl.LinkedEntityId)) {
                designIdToDocId.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
                docIds.add(cdl.ContentDocumentId);
            }
        }

        Map<Id, ContentVersion> docIdToLatest = new Map<Id, ContentVersion>();
        if (!docIds.isEmpty()) {
            for (ContentVersion cv : [SELECT ContentDocumentId, VersionData, Title, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true]) {
                docIdToLatest.put(cv.ContentDocumentId, cv);
            }
        }

        Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
        for(Id designId : designIds) {
            if(designIdToDocId.containsKey(designId)) {
                Id docId = designIdToDocId.get(designId);
                if(docIdToLatest.containsKey(docId)) {
                    result.put(designId, docIdToLatest.get(docId));
                }
            }
        }
        return result;
    }

    /**
     * @description Loop through records, build emails, and send.
     */
    private static void processAndSendEmails(List<Id> designIds, EmailContext ctx) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id designId : designIds) {
            Architecture_Design__c design = ctx.designMap.get(designId);
            if (design == null) {
                continue;
            }

            Messaging.SingleEmailMessage mail = buildSingleEmail(design, ctx);
            
            if (ctx.fileMap.containsKey(designId)) {
                ContentVersion cv = ctx.fileMap.get(designId);
                Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
                attach.setFileName(cv.Title + '.' + cv.FileExtension);
                attach.setBody(cv.VersionData);
                mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
            }

            emails.add(mail);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    /**
     * @description Constructs a single email message object.
     * UPDATED: Concatenates FirstName + LastName to force full name display.
     */
    private static Messaging.SingleEmailMessage buildSingleEmail(Architecture_Design__c design, EmailContext ctx) {
        // Logic to construct Full Name from First/Last to avoid Nicknames
        String supervisorName = '';
        if (design.Opportunity__r != null && design.Opportunity__r.Supervisor_User__r != null) {
            String fname = design.Opportunity__r.Supervisor_User__r.FirstName;
            String lname = design.Opportunity__r.Supervisor_User__r.LastName;
            supervisorName = (fname != null ? fname + ' ' : '') + (lname != null ? lname : '');
            supervisorName = supervisorName.trim(); 
        }

        String approvalLink = buildApprovalLink(ctx.siteBase, design.Id); 

        String html = ctx.template.HtmlValue;
        html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Lead_Name__c}}}', design.Opportunity__r?.Lead_Name__c);
        html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Email__c}}}', design.Opportunity__r?.Email__c);
        html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Supervisor_Name__c}}}', supervisorName);
        html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Supervisor_User_Email__c}}}', design.Opportunity__r?.Supervisor_User__r?.Email);
        html = safeReplace(html, '{{{appointmentApprovalLink}}}', approvalLink);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(safeReplace(ctx.template.Subject, '{{{leadName}}}', design.Opportunity__r?.Lead_Name__c));
        mail.setHtmlBody(html);
        mail.setToAddresses(ctx.toAddresses);
        mail.setOrgWideEmailAddressId(ctx.orgWideId);
        mail.setSaveAsActivity(false);

        return mail;
    }

    // --- Helpers ---

    private static EmailTemplate getEmailTemplate() {
        List<EmailTemplate> templates = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :TEMPLATE_DEVELOPER_NAME LIMIT 1];
        return templates.isEmpty() ? null : templates[0];
    }
    
    private static String buildApprovalLink(String siteBase, Id designId) {
        String pagePath = Label.Manager_Architecture_Approval;
        if (String.isBlank(siteBase) || String.isBlank(pagePath)) {
            return '';
        }
        if (!pagePath.startsWith('/')) {
            pagePath = '/' + pagePath;
        }
        return siteBase + pagePath + '?id=' + designId;
    }

    private static List<String> parseEmailsFromLabel(String labelValue) {
        if (String.isBlank(labelValue)) {
            return new List<String>();
        }
        return labelValue.split('[,;]');
    }

    private static String safeReplace(String source, String token, String value) {
        if (source == null || String.isBlank(token)) {
            return source;
        }
        return source.replace(token, value == null ? '' : value);
    }

    private static Id getDefaultOrgWideEmailAddressId() {
        try {
            return [SELECT Id FROM OrgWideEmailAddress WHERE Address = :Label.Arelia_OWD LIMIT 1].Id;
        } catch(Exception e) { 
            return null; 
        }
    }
}