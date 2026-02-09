/**
 * @description Trigger handler for Architecture_Design__c Manager Approval Emails.
 * Fixed: Moved utility methods to top-level to resolve "static can only be used on methods of a top level type".
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ArchitectureDesignTriggerHandler {

    private static final String STATUS_APPROVED         = 'Approved';
    private static final String TEMPLATE_DEVELOPER_NAME = 'Architecture_Manager_Approval';

    // --- Inner Classes ---

    private class EmailContext {
        public Map<Id, Architecture_Design__c> designMap;
        public Map<Id, ContentVersion> fileMap;
        public EmailTemplate template;
        public List<String> toAddresses;
        public Id orgWideId;
        public String siteBase;
    }

    // --- Trigger Entry Point ---

    public static void onAfterUpdate(List<Architecture_Design__c> newList, Map<Id, Architecture_Design__c> oldMap) {
        List<Id> approvedDesignIds = new List<Id>();

        for (Architecture_Design__c newRec : newList) {
            Architecture_Design__c oldRec = oldMap.get(newRec.Id);
            // Check if Status changed to 'Approved'
            if (newRec.Status__c == STATUS_APPROVED && (oldRec == null || oldRec.Status__c != STATUS_APPROVED)) {
                approvedDesignIds.add(newRec.Id);
            }
        }

        if (!approvedDesignIds.isEmpty()) {
            sendEmailWithAttachment(approvedDesignIds);
        }
    }

    // --- Main Logic ---

    private static void sendEmailWithAttachment(List<Id> designIds) {
        EmailContext ctx = loadEmailContext();
        if (ctx == null) {
            return;
        }

        ctx.designMap = queryDesignData(designIds);
        ctx.fileMap = mapDesignToLatestFile(designIds);

        List<Messaging.SingleEmailMessage> emails = generateEmails(designIds, ctx);
        
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception e) {
                System.debug('Error sending email: ' + e.getMessage());
            }
        }
    }

    // --- Data Loading ---

    private static EmailContext loadEmailContext() {
        EmailContext ctx = new EmailContext();
        
        ctx.toAddresses = parseEmailsFromLabel(Label.Arelia_Living_Enrollment_Members);
        if (ctx.toAddresses.isEmpty()) {
            return null;
        }

        ctx.orgWideId = getDefaultOrgWideEmailAddressId();
        if (ctx.orgWideId == null) {
            return null;
        }

        ctx.template = getEmailTemplate();
        if (ctx.template == null) {
            return null;
        }

        ctx.siteBase = Label.Arelia_Site_Label;
        if (ctx.siteBase != null && ctx.siteBase.endsWith('/')) {
            ctx.siteBase = ctx.siteBase.removeEnd('/');
        }
        return ctx;
    }

    private static Map<Id, Architecture_Design__c> queryDesignData(List<Id> designIds) {
        return new Map<Id, Architecture_Design__c>([
            SELECT Id, 
                   Status__c,        
                   Comments__c,      
                   Opportunity__c,
                   Opportunity__r.Name, 
                   Opportunity__r.Project_Description__c,
                   Opportunity__r.Site_Space__c,
                   Opportunity__r.Lead_Name__c,
                   Opportunity__r.Email__c,
                   Opportunity__r.Lead_Phone__c,
                   Opportunity__r.Supervisor_User__r.FirstName, 
                   Opportunity__r.Supervisor_User__r.LastName,
                   Opportunity__r.Supervisor_User__r.Email,
                   Project__r.Name
            FROM Architecture_Design__c
            WHERE Id IN :designIds
        ]);
    }

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

    // --- Email Construction ---

    private static List<Messaging.SingleEmailMessage> generateEmails(List<Id> designIds, EmailContext ctx) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id designId : designIds) {
            Architecture_Design__c design = ctx.designMap.get(designId);
            if (design == null) {
                continue;
            }

            Messaging.SingleEmailMessage mail = buildSingleEmail(design, ctx);
            
            // Attach File if exists
            if (ctx.fileMap.containsKey(designId)) {
                ContentVersion cv = ctx.fileMap.get(designId);
                Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
                attach.setFileName(cv.Title + '.' + cv.FileExtension);
                attach.setBody(cv.VersionData);
                mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
            }
            emails.add(mail);
        }
        return emails;
    }

    private static Messaging.SingleEmailMessage buildSingleEmail(Architecture_Design__c design, EmailContext ctx) {
        // 1. Prepare Merge Data
        Map<String, String> placeholders = prepareMergeMap(design, ctx.siteBase);

        // 2. Replace Body Placeholders
        // FIX: Calling static method directly (moved from inner class)
        String html = applyReplacements(ctx.template.HtmlValue, placeholders);
        
        // 3. Replace Subject Placeholders
        String subject = safeReplace(ctx.template.Subject, '{{{leadName}}}', design.Opportunity__r?.Lead_Name__c);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(subject);
        mail.setHtmlBody(html);
        mail.setToAddresses(ctx.toAddresses);
        mail.setOrgWideEmailAddressId(ctx.orgWideId);
        mail.setSaveAsActivity(false);

        return mail;
    }

    /**
     * @description Prepares the map of tokens to values. 
     */
    private static Map<String, String> prepareMergeMap(Architecture_Design__c des, String siteBase) {
        Map<String, String> m = new Map<String, String>();
        
        // 1. Calculations
        String supervisorName = '';
        if (des.Opportunity__r != null && des.Opportunity__r.Supervisor_User__r != null) {
            String f = des.Opportunity__r.Supervisor_User__r.FirstName;
            String l = des.Opportunity__r.Supervisor_User__r.LastName;
            supervisorName = ((f != null ? f : '') + ' ' + (l != null ? l : '')).trim();
        }

        String approvalLink = buildApprovalLink(siteBase, des.Id);
        
        String projectName = (des.Opportunity__r != null) ? des.Opportunity__r.Name : 
                             (des.Project__r != null) ? des.Project__r.Name : 'Unknown Project';

        String clientName = (des.Opportunity__r != null && des.Opportunity__r.Lead_Name__c != null) 
                            ? des.Opportunity__r.Lead_Name__c : 'Valued Client';

        // 2. Populate Map
        m.put('[PROJECT_NAME]', projectName);
        m.put('[PROJECT_DESCRIPTION]', getField(des.Opportunity__r?.Project_Description__c));
        m.put('[SITE_SPACE]', getField(des.Opportunity__r?.Site_Space__c));
        m.put('[CLIENT_NAME]', clientName);
        m.put('[CLIENT_EMAIL]', getField(des.Opportunity__r?.Email__c));
        m.put('[CLIENT_PHONE]', getField(des.Opportunity__r?.Lead_Phone__c));
        m.put('[CLIENT_DECISION]', getField(des.Status__c));
        m.put('[CLIENT_REMARKS]', getField(des.Comments__c));
        m.put('[SUPERVISOR_NAME]', supervisorName);
        m.put('[SUPERVISOR_EMAIL]', getField(des.Opportunity__r?.Supervisor_User__r?.Email));
        m.put('[APPROVAL_LINK]', approvalLink);

        return m;
    }

    // --- Utilities ---

    private static EmailTemplate getEmailTemplate() {
        List<EmailTemplate> templates = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :TEMPLATE_DEVELOPER_NAME LIMIT 1];
        return templates.isEmpty() ? null : templates[0];
    }
    
    private static String buildApprovalLink(String siteBase, Id designId) {
        String pagePath = Label.Manager_Architecture_Approval;
        if (String.isBlank(siteBase) || String.isBlank(pagePath)) {
            return '#';
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

    private static Id getDefaultOrgWideEmailAddressId() {
        try {
            return [SELECT Id FROM OrgWideEmailAddress WHERE Address = :Label.Arelia_OWD LIMIT 1].Id;
        } catch(Exception e) { 
            return null; 
        }
    }

    // --- REPLACEMENT UTILITIES (Moved to Top Level) ---

    private static String safeReplace(String source, String token, String value) {
        if (source == null || String.isBlank(token)) {
            return source;
        }
        return source.replace(token, value == null ? '' : value);
    }

    private static String getField(String val) {
        return (val != null) ? val : '';
    }

    private static String applyReplacements(String source, Map<String, String> tokenMap) {
        if (String.isBlank(source)) {
            return '';
        }
        String result = source;
        for (String token : tokenMap.keySet()) {
            String val = tokenMap.get(token);
            result = result.replace(token, val);
        }
        return result;
    }
}