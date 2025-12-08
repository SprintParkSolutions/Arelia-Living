public without sharing class LeadEmailHandler {

    /**
     * Sends appropriate emails when lead is approved:
     *  - Email to Lead (Details_To_Lead)
     *  - Email to Management (Details_To_Management)
     */
    public static void sendEmailForLead(Lead leadRecord) {
        if (leadRecord == null || String.isBlank(leadRecord.Email)) {
            return;
        }

        try {
            List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();

            // ========== When Approved: Send BOTH emails ==========
            if (leadRecord.Approval_Status__c == 'Approved') {

                // 1️⃣ Email to Lead
                Id leadTemplateId = getTemplateIdByDeveloperName(Label.Arelia_Living_Lead_Email_Template);
                if (leadTemplateId != null) {
                    emailMessages.add(prepareLeadEmail(leadRecord.Id, leadTemplateId));
                }

                // 2️⃣ Email to Management
                Id managementTemplateId = getTemplateIdByDeveloperName(Label.Arelia_Living_Management_Email_Template);
                if (managementTemplateId != null) {
                    emailMessages.addAll(prepareManagementEmails(leadRecord, managementTemplateId));
                }
            }

            // Send all emails
            if (!emailMessages.isEmpty()) {
                sendEmails(emailMessages);
            }

        } catch (Exception ex) {
            throw new AuraHandledException('Failed to send email notifications: ' + ex.getMessage());
        }
    }

    // ========== Get Email Template by API Name ==========
    private static Id getTemplateIdByDeveloperName(String devName) {
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate
            WHERE DeveloperName = :devName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    // ========== Email to Lead ==========
    private static Messaging.SingleEmailMessage prepareLeadEmail(Id leadId, Id templateId) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTargetObjectId(leadId);
        email.setTemplateId(templateId);
        email.setTreatTargetObjectAsRecipient(true);
        email.setSaveAsActivity(true);
        email.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());
        return email;
    }

    // ========== Emails to Management ==========
    private static List<Messaging.SingleEmailMessage> prepareManagementEmails(Lead leadRecord, Id templateId) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<String> allEmailAddresses = new List<String>();

        // Emails from custom label 
        if (!String.isBlank(Label.Arelia_Living_Enrollment_Members)) {
            allEmailAddresses.addAll(Label.Arelia_Living_Enrollment_Members.split(','));
        }

        // Emails from Manager Role
        allEmailAddresses.addAll(getManagerEmailsByRole());

        // Emails from Enrollment Role
        allEmailAddresses.addAll(getEnrollmentEmailsByRole());

        // Unique email addresses
        Set<String> uniqueEmails = new Set<String>();

        for (String emailAddr : allEmailAddresses) {
            String trimmed = emailAddr != null ? emailAddr.trim() : '';
            if (String.isNotBlank(trimmed) && uniqueEmails.add(trimmed)) {

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ trimmed });
                msg.setTemplateId(templateId);
                msg.setTargetObjectId(leadRecord.Id);
                msg.setTreatTargetObjectAsRecipient(false);
                msg.setSaveAsActivity(true);
                msg.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

                emails.add(msg);
            }
        }

        return emails;
    }

    // ========== Send All Emails ==========
    private static void sendEmails(List<Messaging.SingleEmailMessage> messages) {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);

        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                for (Messaging.SendEmailError error : result.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Email send error: ' + error.getMessage());
                }
            }
        }
    }

    // ========== Org-Wide Email ==========
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD
            // AND IsAllowAllProfiles = true
            LIMIT 1
        ];

        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    // ========== Get Manager Emails ==========
    private static List<String> getManagerEmailsByRole() {
        List<String> emails = new List<String>();
        for (User u : [
            SELECT Email FROM User
            WHERE UserRole.Name LIKE '%Manager%'
            AND IsActive = true
            AND Email != null
        ]) {
            emails.add(u.Email.trim());
        }
        return emails;
    }

    // ========== Get Enrollment Emails ==========
    private static List<String> getEnrollmentEmailsByRole() {
        List<String> emails = new List<String>();
        for (User u : [
            SELECT Email FROM User
            WHERE UserRole.Name LIKE '%Enrollment%'
            AND IsActive = true
            AND Email != null
        ]) {
            emails.add(u.Email.trim());
        }
        return emails;
    }
}
