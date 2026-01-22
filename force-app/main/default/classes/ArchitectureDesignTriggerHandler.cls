/**
 * @description
 *  Trigger handler for Architecture_Design__c:
 *    • Detects when Status__c changes to 'Approved'
 *    • Sends manager-approval email:
 *        - To addresses from Label.Arelia_Living_Enrollment_Members
 *        - From Org-Wide Email in Label.Arelia_OWD
 *        - Using EmailTemplate DeveloperName 'Architecture_Manager_Approval'
 *        - Replacing custom placeholders in HTML body using String.replace()
 *        - Builds approval link and replaces {{{appointmentApprovalLink}}}
 *        - Attaching latest ContentVersion linked to the design
 */
@SuppressWarnings('PMD.ApexCRUDViolation, PMD.CognitiveComplexity')
public without sharing class ArchitectureDesignTriggerHandler {

    private static final String STATUS_APPROVED         = 'Approved';
    private static final String TEMPLATE_DEVELOPER_NAME = 'Architecture_Manager_Approval';

    /* =========================================================
       ENTRY POINT FROM TRIGGER
    ========================================================== */
    public static void onAfterUpdate(
        List<Architecture_Design__c> newList,
        Map<Id, Architecture_Design__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        List<Id> approvedDesignIds = new List<Id>();

        for (Architecture_Design__c newRec : newList) {
            Architecture_Design__c oldRec = oldMap.get(newRec.Id);

            if (newRec.Status__c == STATUS_APPROVED &&
                (oldRec == null || oldRec.Status__c != STATUS_APPROVED)) {

                approvedDesignIds.add(newRec.Id);
            }
        }

        if (!approvedDesignIds.isEmpty()) {
            sendEmailWithAttachment(approvedDesignIds);
        }
    }

    /* =========================================================
       EMAIL + ATTACHMENT LOGIC
    ========================================================== */
    private static void sendEmailWithAttachment(List<Id> designIds) {
        if (designIds == null || designIds.isEmpty()) {
            return;
        }

        // 1) Recipients from label
        List<String> toAddresses = parseEmailsFromLabel(Label.Arelia_Living_Enrollment_Members);
        if (toAddresses.isEmpty()) {
            return;
        }

        // 2) Org-Wide Email Address from label
        Id orgWideId = getDefaultOrgWideEmailAddressId();

        // 3) Base site (remove trailing slash)
        String siteBase = Label.Arelia_Site_Label;
        if (siteBase != null && siteBase.endsWith('/')) {
            siteBase = siteBase.removeEnd('/');
        }

        // 4) Template lookup
        List<EmailTemplate> etList = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :TEMPLATE_DEVELOPER_NAME
            LIMIT 1
        ];
        if (etList.isEmpty()) {
            return;
        }
        EmailTemplate template = etList[0];

        // 5) Load Architecture Designs with related Opportunity fields
        Map<Id, Architecture_Design__c> designMap = new Map<Id, Architecture_Design__c>([
            SELECT Id,
                   Opportunity__c,
                   Opportunity__r.Lead_Name__c,
                   Opportunity__r.Email__c,
                   Opportunity__r.Supervisor_Name__c,
                   Opportunity__r.Supervisor_User_Email__c
            FROM Architecture_Design__c
            WHERE Id IN :designIds
        ]);

        // 6) Preload attachments (CDL + ContentVersion)
        Map<Id, Id> designIdToDocId = new Map<Id, Id>();
        Set<Id> docIds = new Set<Id>();

        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :designIds
        ]) {
            if (!designIdToDocId.containsKey(cdl.LinkedEntityId)) {
                designIdToDocId.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
                docIds.add(cdl.ContentDocumentId);
            }
        }

        Map<Id, ContentVersion> docIdToLatest = new Map<Id, ContentVersion>();
        if (!docIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT ContentDocumentId, VersionData, Title, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
            ]) {
                docIdToLatest.put(cv.ContentDocumentId, cv);
            }
        }

        // 7) Build emails
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id designId : designIds) {
            Architecture_Design__c design = designMap.get(designId);
            if (design == null) {
                continue;
            }

            try {
                // Null-safe values
                String leadName        = (design.Opportunity__r != null) ? design.Opportunity__r.Lead_Name__c : '';
                String clientEmail     = (design.Opportunity__r != null) ? design.Opportunity__r.Email__c : '';
                String supervisorName  = (design.Opportunity__r != null) ? design.Opportunity__r.Supervisor_Name__c : '';
                String supervisorEmail = (design.Opportunity__r != null) ? design.Opportunity__r.Supervisor_User_Email__c : '';

                // ✅ Approval Link (same style as your example)
                // This passes Opportunity Id in query param. If you want Design Id, replace design.Opportunity__c with design.Id.
                String approvalLink = buildApprovalLink(siteBase, design.Opportunity__c);

                // ✅ Replace tokens exactly like your Opportunity method
                String html = template.HtmlValue;
                html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Lead_Name__c}}}', leadName);
                html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Email__c}}}', clientEmail);
                html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Supervisor_Name__c}}}', supervisorName);
                html = safeReplace(html, '{{{Architecture_Design__c.Opportunity__r.Supervisor_User_Email__c}}}', supervisorEmail);

                // ✅ Link token replacement (keep this token in your template)
                html = safeReplace(html, '{{{appointmentApprovalLink}}}', approvalLink);

                // (Optional) If your template still contains [SITE_URL], replace it too
                html = safeReplace(html, '[SITE_URL]', siteBase);

                String subject = template.Subject;
                // If your subject contains any tokens, replace similarly (optional)
                subject = safeReplace(subject, '{{{leadName}}}', leadName);

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setUseSignature(false);
                mail.setSaveAsActivity(false);
                mail.setSubject(subject);
                mail.setHtmlBody(html);
                mail.setToAddresses(toAddresses);

                if (orgWideId != null) {
                    mail.setOrgWideEmailAddressId(orgWideId);
                }

                // Attach latest file if any
                Id docId = designIdToDocId.get(designId);
                if (docId != null) {
                    ContentVersion cv = docIdToLatest.get(docId);
                    if (cv != null) {
                        Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
                        attach.setFileName(cv.Title + '.' + cv.FileExtension);
                        attach.setBody(cv.VersionData);
                        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
                    }
                }

                emails.add(mail);

            } catch (Exception e) {
                System.debug('### Email build failed for Architecture Design Id=' + designId + ' => ' + e.getMessage());
                System.debug(e.getStackTraceString());
            }
        }

        // 8) Send
        if (!emails.isEmpty()) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess() && results[i].getErrors() != null && !results[i].getErrors().isEmpty()) {
                    System.debug('### FAILED email ' + i + ': ' + results[i].getErrors()[0].getMessage());
                }
            }
        }
    }

    /* =========================================================
       HELPERS
    ========================================================== */

    // ✅ Same style as you requested: Label.Arelia_Site_Label + Label.Site_Appointment_Opp_Link_Page + '?id=' + id
    private static String buildApprovalLink(String siteBase, Id oppId) {
        String pagePath = Label.Arelia_Site_Label + Label.Site_Appointment_Opp_Link_Page;
        if (String.isBlank(siteBase) || String.isBlank(pagePath) || oppId == null) {
            return '';
        }
        if (!pagePath.startsWith('/')) {
            pagePath = '/' + pagePath;
        }
        return siteBase + pagePath + '?id=' + String.valueOf(oppId);
    }

    private static List<String> parseEmailsFromLabel(String labelValue) {
        List<String> emails = new List<String>();
        if (String.isBlank(labelValue)) {
            return emails;
        }
        for (String email : labelValue.split('[,;]')) {
            if (String.isNotBlank(email)) {
                emails.add(email.trim());
            }
        }
        return emails;
    }

    private static String safeReplace(String source, String token, String value) {
        if (source == null || String.isBlank(token)) {
            return source;
        }
        return source.replace(token, value == null ? '' : value);
    }

    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owd = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD
              AND IsAllowAllProfiles = true
            LIMIT 1
        ];
        return owd.isEmpty() ? null : owd[0].Id;
    }
}
