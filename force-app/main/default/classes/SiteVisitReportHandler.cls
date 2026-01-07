/**
 * Utility class to send approval emails for Site Visit Reports.
 * Emails are sent to management emails from a custom label using a predefined email template.
 */
public with sharing class SiteVisitReportHandler {

    /**
     * Sends approval notification emails for the given Site Visit Report IDs.
     * NOTE: Lead status syncing is handled separately so that we also sync for non-Approved statuses.
     *
     * @param reportIds List of Site_Visit_Report__c record IDs
     */
    public static void sendApprovalEmails(List<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {
            return;
        }

        // Fetch reports with needed fields and related records
        List<Site_Visit_Report__c> reports = [
            SELECT Id, Name, Site_Visit_Date__c, Site_Visit_Time_Slot__c, Site_Visit_Report_Status__c,
                   Estimated_Completion_Date__c, Total_Estimated_Cost__c, Opportunity__c,Opportunity__r.Name,
                   Supervisor_User__r.Name, Supervisor_User__r.Phone,
                   Lead__r.FirstName, Lead__r.LastName, Lead__r.Email, Lead__r.Phone, Lead__r.Company,
                   Lead__r.Estimated_Start_Date__c, Lead__r.Status, Lead__r.Approval_Status__c,
                   RecordType.DeveloperName
            FROM Site_Visit_Report__c 
            WHERE Id IN :reportIds
        ];

        if (reports.isEmpty()) {
            return;
        }

        // Collect recipients
        List<String> allEmailAddresses = new List<String>();
        allEmailAddresses.addAll(getManagerEmailsByRole());
        allEmailAddresses.addAll(getManagementEmails());

        if (allEmailAddresses.isEmpty()) {
            return;
        }

        // Prepare email messages for each report
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Site_Visit_Report__c report : reports) {

            // ✅ Pick correct template based on record type
            String templateName;
            if (report.RecordType.DeveloperName == 'Opportunity_Site_Visit_Report') {
                templateName = Label.Arelia_Living_Opportunity_Re_Visit_Site_Manager_Approval_Email_Template;
            } else {
                templateName = Label.Arelia_Living_Lead_Conversion_Approval_Email_Template;
            }

            EmailTemplate selectedTemplate = fetchEmailTemplateByName(templateName);
            if (selectedTemplate == null) {
                continue;
            }

            String htmlBody = populateTemplate(selectedTemplate.HtmlValue, report);
            String subject = populateSubject(selectedTemplate.Subject, report);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(allEmailAddresses);
            email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
            email.setSubject(subject);
            email.setHtmlBody(htmlBody);
            email.setSaveAsActivity(true);
            emails.add(email);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                System.debug('Error sending approval emails: ' + e.getMessage());
            }
        }
    }

    // Helper to get and clean management emails from label
    private static List<String> getManagementEmails() {
        String mgmtEmails = Label.Arelia_Living_Enrollment_Members;
        List<String> emails = new List<String>();
        if (String.isNotBlank(mgmtEmails)) {
            for (String email : mgmtEmails.split(',')) {
                String trimmed = email.trim();
                if (trimmed != '') {
                    emails.add(trimmed);
                }
            }
        }
        return emails;
    }

    /**
     * Helper method to fetch template by DeveloperName
     */
    private static EmailTemplate fetchEmailTemplateByName(String templateName) {
        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :templateName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    // Replace merge fields in email body
    private static String populateTemplate(String templateHtml, Site_Visit_Report__c report) {
        if (templateHtml == null) {
            return '';
        }
        Id SiteVisitReportId = report.Id;
        String siteVisitRecordPageLink = Label.Arelia_Site_Label + 'detail/' + SiteVisitReportId;
        System.debug('SiteVisitReportId: ' + SiteVisitReportId );
        return templateHtml
            .replace('{{{Site_Visit_Report__c.Supervisor_User__r.Name}}}', safeString(report.Supervisor_User__r?.Name))
            .replace('{{{Site_Visit_Report__c.Supervisor_User__r.Phone}}}', safeString(report.Supervisor_User__r?.Phone))
            .replace('{{{Site_Visit_Report__c.Lead__r.FirstName}}}', safeString(report.Lead__r?.FirstName))
            .replace('{{{Site_Visit_Report__c.Lead__r.LastName}}}', safeString(report.Lead__r?.LastName))
            .replace('{{{Site_Visit_Report__c.Lead__r.Email}}}', safeString(report.Lead__r?.Email))
            .replace('{{{Site_Visit_Report__c.Lead__r.Phone}}}', safeString(report.Lead__r?.Phone))
            .replace('{{{Site_Visit_Report__c.Lead__r.Company}}}', safeString(report.Lead__r?.Company))
            .replace('{{{Site_Visit_Report__c.Lead__r.Estimated_Start_Date__c}}}', formatDate(report.Lead__r?.Estimated_Start_Date__c))
            .replace('{{{Site_Visit_Report__c.Lead__r.Status}}}', safeString(report.Lead__r?.Status))
            .replace('{{{Site_Visit_Report__c.Lead__r.Approval_Status__c}}}', safeString(report.Lead__r?.Approval_Status__c))
             .replace('{{{Site_Visit_Report__c.Opportunity__r.Name}}}', safeString(report.Opportunity__r?.Name))
            .replace('{{{Site_Visit_Report__c.Name}}}', safeString(report.Name))
            .replace('{{{SiteVisitReportId}}}', safeString(SiteVisitReportId))
            .replace('{{{Site_Visit_Report__c.Site_Visit_Date__c}}}', formatDate(report.Site_Visit_Date__c))
            .replace('{{{Site_Visit_Report__c.Site_Visit_Time_Slot__c}}}', safeString(report.Site_Visit_Time_Slot__c))
            .replace('{{{Site_Visit_Report__c.Site_Visit_Report_Status__c}}}', safeString(report.Site_Visit_Report_Status__c))
            .replace('{{{Site_Visit_Report__c.Estimated_Completion_Date__c}}}', formatDate(report.Estimated_Completion_Date__c))
            .replace('{{{Site_Visit_Report__c.Total_Estimated_Cost__c}}}', safeString(report.Total_Estimated_Cost__c))
            .replace('{{{siteVisitRecordPageLink}}}', siteVisitRecordPageLink);
    }

    // Replace merge fields in email subject
    private static String populateSubject(String subject, Site_Visit_Report__c report) {
        if (subject == null) {
            return '';
        }
        return subject.replace('{{{Site_Visit_Report__c.Supervisor_User__r.Name}}}', safeString(report.Supervisor_User__r?.Name));
    }

    // Null-safe string conversion
    private static String safeString(Object obj) {
        return obj != null ? String.valueOf(obj) : '';
    }

    // Format Date
    private static String formatDate(Date dt) {
        return dt != null ? dt.format() : '';
    }

    // Format Datetime
    private static String formatDateTime(Datetime dt) {
        return dt != null ? dt.format() : '';
    }

    // Format decimal as currency string with $ prefix
    private static String formatCurrency(Decimal amount) {
        return amount != null ? '$' + amount.format() : '';
    }

    // Get org-wide email address Id for sending
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> addresses = [SELECT Id FROM OrgWideEmailAddress
                                                WHERE Address = :Label.Arelia_OWD LIMIT 1];
        return addresses.isEmpty() ? null : addresses[0].Id;
    }

    /**
     * @description Fetches manager user emails based on role name.
     *              Adjust role name logic as needed for your org.
     * @return List of manager email addresses.
     */
    private static List<String> getManagerEmailsByRole() {
        List<String> managerEmails = new List<String>();
        for (User u : [
            SELECT Email
            FROM User
            WHERE UserRole.Name LIKE '%Manager%'
              AND IsActive = true
              AND Email != null
        ]) {
            managerEmails.add(u.Email.trim());
        }
        return managerEmails;
    }

    // ======================================================================
    // Orchestration called by the trigger (keeps trigger free of logic)
    // ======================================================================

    /**
     * AFTER INSERT behavior (same as before):
     * - Attach files to the related Lead for each Site Visit Report.
     */
    public static void afterInsert(List<Site_Visit_Report__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        for (Site_Visit_Report__c svr : newList) {
            if (svr == null) {
                continue;
            }
            SiteVisitReportFileService.attachFilesToLead(svr.Id);
        }
    }

    /**
     * AFTER UPDATE behavior:
     * 1) Attach files to Lead for each record (same as before)
     * 2) Sync Lead fields (status/date) for ALL statuses when they change
     * 3) When status changes to "Approved", send approval emails
     * 4) Call SiteVisitApprovalController.handleAfterUpdate (unchanged)
     */
    public static void afterUpdate(List<Site_Visit_Report__c> newList, Map<Id, Site_Visit_Report__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        // Part 1: Attach files to Lead
        for (Site_Visit_Report__c svr : newList) {
            if (svr == null) {
                continue;
            }
            SiteVisitReportFileService.attachFilesToLead(svr.Id);
        }

        // Part 2: Sync parent (Lead/Opportunity) for any status/date change. (e.g., Approved, Negotiable, etc.)
        List<Site_Visit_Report__c> reportsNeedingSync = new List<Site_Visit_Report__c>();
        for (Site_Visit_Report__c newRec : newList) {
            if (newRec == null) {continue;}
            Site_Visit_Report__c oldRec = oldMap.get(newRec.Id);

            Boolean statusChanged = (oldRec == null)
                ? String.isNotBlank(newRec.Site_Visit_Report_Status__c)
                : newRec.Site_Visit_Report_Status__c != oldRec.Site_Visit_Report_Status__c;

            Boolean endDateChanged = (oldRec == null)
                ? (newRec.Estimated_Completion_Date__c != null)
                : (newRec.Estimated_Completion_Date__c != oldRec.Estimated_Completion_Date__c);

            if (statusChanged || endDateChanged) {
                reportsNeedingSync.add(newRec);
            }
        }
        if (!reportsNeedingSync.isEmpty()) {
            syncParentsFromReports(reportsNeedingSync);
        }


        // Part 3: Send emails only when status changed to "Approved"
        List<Id> approvedReportIds = new List<Id>();
        for (Site_Visit_Report__c newRec : newList) {
            if (newRec == null) {
                continue;
            }
            Site_Visit_Report__c oldRec = oldMap.get(newRec.Id);
            if (oldRec != null
                && newRec.Site_Visit_Report_Status__c == 'Approved'
                && oldRec.Site_Visit_Report_Status__c != 'Approved') {
                approvedReportIds.add(newRec.Id);
            }
        }
        if (!approvedReportIds.isEmpty()) {
            SiteVisitReportHandler.sendApprovalEmails(approvedReportIds);
        }

        // Part 4: Existing downstream call (unchanged)
        // SiteVisitApprovalController.handleAfterUpdate(newList, oldMap);
    }


    /**
     * Syncs status/date from Site Visit Reports to the correct parent record
     * based on Report Record Type:
     *  - Lead_Site_Visit_Report         -> Lead fields
     *  - Opportunity_Site_Visit_Report  -> Opportunity fields
     *
     * Runs for any non-blank status (Approved, Negotiable, etc.).
     */
    private static void syncParentsFromReports(List<Site_Visit_Report__c> reports) {
        if (reports == null || reports.isEmpty()) {return;}

        // We'll need RecordType developer names; collect RT Ids first (from trigger context we have only Ids)
        Set<Id> rtIds = new Set<Id>();
        for (Site_Visit_Report__c r : reports) {
            if (r != null && r.RecordTypeId != null) {rtIds.add(r.RecordTypeId);}
        }

        Map<Id, RecordType> rtById = new Map<Id, RecordType>();
        if (!rtIds.isEmpty()) {
            rtById = new Map<Id, RecordType>([SELECT Id, DeveloperName FROM RecordType WHERE Id IN :rtIds]);
        }

        // Prepare upserts for Leads and Opportunities
        Map<Id, Lead> leadUpdates = new Map<Id, Lead>();
        Map<Id, Opportunity> oppUpdates = new Map<Id, Opportunity>();

        for (Site_Visit_Report__c r : reports) {
            if (r == null) {continue;}
            if (String.isBlank(r.Site_Visit_Report_Status__c)) {continue;} // don't overwrite with blank

            String rtName = (r.RecordTypeId != null && rtById.containsKey(r.RecordTypeId))
                ? rtById.get(r.RecordTypeId).DeveloperName
                : null;

            // Route to the correct parent based on record type
            if (rtName == 'Opportunity_Site_Visit_Report') {
                if (r.Opportunity__c != null) {
                    Opportunity up = new Opportunity(
                        Id = r.Opportunity__c,
                        Re_Visit_Site_Status__c = r.Site_Visit_Report_Status__c,
                        Re_Visit_Site_Supervisor_Completion_Date__c = r.Estimated_Completion_Date__c
                    );
                    oppUpdates.put(up.Id, up);
                }
            } else { // default to Lead_Site_Visit_Report (or any non-opp RT)
                if (r.Lead__c != null) {
                    Lead up = new Lead(
                        Id = r.Lead__c,
                        Site_Visit_Status__c = r.Site_Visit_Report_Status__c,
                        Project_End_Date_by_Supervisor__c = r.Estimated_Completion_Date__c
                    );
                    leadUpdates.put(up.Id, up);
                }
            }
        }

        // DML (separate try/catch to avoid blocking each other)
        if (!leadUpdates.isEmpty()) {
            try { update leadUpdates.values(); }
            catch (Exception ex) {
                System.debug('Error syncing Lead from Site Visit Report: ' + ex.getMessage());
            }
        }
        if (!oppUpdates.isEmpty()) {
            try { update oppUpdates.values(); }
            catch (Exception ex) {
                System.debug('Error syncing Opportunity from Site Visit Report: ' + ex.getMessage());
            }
        }
    }
}