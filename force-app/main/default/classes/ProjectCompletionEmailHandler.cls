/**
 * @File Name         : ProjectCompletionEmailHandler.cls
 * @Description       : Central handler to send project-completion emails
 *                      to Client, Supervisor, Managers (role-based) and
 *                      additional management/enrollment members from label.
 *
 *                      This class is intended to be invoked from an
 *                      AFTER UPDATE trigger on Project__c when a project
 *                      first reaches:
 *                      - Status__c                = 'Completed'
 *                      - Project_Completion_Status__c = 100
 *
 * @Author            : 
 * @Created Date      : 
 * @Last Modified By  : 
 * @Last Modified On  : 
 *
 * @Modification Log  :
 * =============================================================================
 * Ver   | Date       | Author   | Modification
 * =============================================================================
 * 1.0   |            |          | Initial Version
 * =============================================================================
 *
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class ProjectCompletionEmailHandler {

    // ========================================================================
    // Constant Template API Names
    // ========================================================================

    /** Email template (API name) for client notification when project completes. */
    private static final String CLIENT_TPL_COMPLETED     = 'Client_Project_Completed_Notification';

    /** Email template (API name) for supervisor notification when project completes. */
    private static final String SUPERVISOR_TPL_COMPLETED = 'Supervisor_Project_Completed_Notification';

    /** Email template (API name) for manager notification when project completes. */
    private static final String MANAGER_TPL_COMPLETED    = 'Sending_Project_Completed_Information_to_Manager';

    /** Email template (API name) for management distribution list notification. */
    private static final String MGMT_TPL                 = 'Sending_Project_Completed_Information_to_Management';

    /** Email template (API name) for enrollment-related notification. */
    private static final String ENROLL_TPL               = 'Sending_Project_Completed_Information_to_Enrollment';

    // ========================================================================
    // Custom Labels
    // ========================================================================

    /** Org-Wide Email Address label used as the FROM address for outbound mails. */
    private static final String DEFAULT_OWD_EMAIL = System.Label.Arelia_OWD;

    /**
     * Label containing comma-separated email addresses for management/enrollment
     * members to be notified when a project is completed.
     */
    private static final String MGMT_LABEL_CSV    = System.Label.Arelia_Living_Enrollment_Members;

    // =========================================================================
    // Entry from AFTER UPDATE trigger
    // =========================================================================
    /**
     * Entry point from the Project__c AFTER UPDATE trigger.
     * Identifies records that have just transitioned to:
     *   - Status__c = 'Completed'
     *   - Project_Completion_Status__c = 100
     * and delegates the email sending to sendProjectApprovedEmail.
     *
     * @param newList List<Project__c> new versions from trigger
     * @param oldMap  Map<Id, Project__c> old versions from trigger
     */
    public static void handleAfterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<Project__c> justCompleted = new List<Project__c>();
        for (Project__c n : newList) {
            Project__c o = oldMap.get(n.Id);
            if (o == null) {
                continue;
            }
            Boolean nowCompleted = (n.Status__c == 'Completed' && n.Project_Completion_Status__c == 100);
            Boolean wasCompleted = (o.Status__c == 'Completed' && o.Project_Completion_Status__c == 100);
            if (nowCompleted && !wasCompleted) {
                justCompleted.add(n);
            }
        }

        if (!justCompleted.isEmpty()) {
            // PMD: CognitiveComplexity is already reduced here by delegating
            // to sendProjectApprovedEmail; further splitting would reduce
            // readability, so we keep this as the central filter.
            sendProjectApprovedEmail(justCompleted);
        }
    }

    // =========================================================================
    // Orchestrator (kept small for readability)
    // =========================================================================
    /**
     * Main orchestrator to send project-completion emails.
     * For each completed project it:
     *  - Loads related Client (Contact) and Supervisor (User)
     *  - Loads templates (client, supervisor, manager, management/enrollment)
     *  - Finds role-based managers
     *  - Builds final Messaging.SingleEmailMessage instances
     *  - Sends all emails in a single Messaging.sendEmail call
     *
     * @param projects List<Project__c> that have just reached "Completed @ 100%".
     */
    public static void sendProjectApprovedEmail(List<Project__c> projects) {
        if (projects == null || projects.isEmpty()) {
            return;
        }

        try {
            Map<Id, Contact> contactMap = getClientContacts(projects);
            Map<Id, User>    supMap     = getSupervisorUsers(projects);

            Templates tpls = loadTemplates();
            List<User> roleManagers = getManagersByRole();

            List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();
            for (Project__c proj : projects) {
                Contact client = contactMap.get(proj.Client__c);
                User    sup    = supMap.get(proj.Supervisor_User__c);

                // Build & aggregate all emails for this project
                outbox.addAll(buildClientEmails(proj, client, sup, tpls));
                outbox.addAll(buildSupervisorEmails(proj, client, sup, tpls));
                outbox.addAll(buildRoleManagerEmails(proj, client, sup, tpls, roleManagers));
                outbox.addAll(buildCsvLabelEmails(proj, client, sup, tpls.management, MGMT_LABEL_CSV));
            }

            if (!outbox.isEmpty()) {
                // PMD: We intentionally send in a single call to respect
                // governor limits and keep the orchestration simple.
                Messaging.sendEmail(outbox);
            }
        } catch (Exception e) {
            // PMD: Logging via System.debug is acceptable here because this
            // is a backend handler and we avoid surfacing errors to end users.
            System.debug(LoggingLevel.ERROR, 'Error sending project completion emails: ' + e.getMessage());
        }
    }

    // =========================================================================
    // Template container (DTO)
    // =========================================================================
    /**
     * Simple DTO to hold all templates so that we only query once.
     */
    private class Templates {
        EmailTemplate client;
        EmailTemplate supervisor;
        EmailTemplate manager;
        EmailTemplate management;
        EmailTemplate enrollment;
    }

    /**
     * Loads and caches all required templates for this handler.
     *
     * @return Templates wrapper with client/supervisor/manager/management/enrollment templates.
     */
    private static Templates loadTemplates() {
        Templates t = new Templates();
        t.client     = fetchEmailTemplate(CLIENT_TPL_COMPLETED);
        t.supervisor = fetchEmailTemplate(SUPERVISOR_TPL_COMPLETED);
        t.manager    = fetchEmailTemplate(MANAGER_TPL_COMPLETED);
        t.management = fetchEmailTemplate(MGMT_TPL);
        t.enrollment = fetchEmailTemplate(ENROLL_TPL);
        return t;
    }

    // =========================================================================
    // Email builders (for different audiences)
    // =========================================================================
    /**
     * Builds completion email(s) for the Client.
     * If a Contact with email exists, uses setTargetObjectId,
     * otherwise falls back to a direct email address on the Project.
     *
     * @param proj   Project__c record
     * @param client Related Contact (Client__c)
     * @param sup    Supervisor User
     * @param tpls   Container for all templates
     * @return List of SingleEmailMessage for client notification.
     */
    private static List<Messaging.SingleEmailMessage> buildClientEmails(
        Project__c proj, Contact client, User sup, Templates tpls
    ) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tpls == null || tpls.client == null) {
            return listMsgs;
        }

        String fallback = String.valueOf(proj.get('Client_Email__c'));
        String to = (client != null && String.isNotBlank(client.Email)) ? client.Email : fallback;
        if (String.isBlank(to)) {
            return listMsgs;
        }

        String subj = replaceVars(tpls.client.Subject,  proj, client, sup, null);
        String body = replaceVars(tpls.client.HtmlValue, proj, client, sup, null);

        if (client != null && String.isNotBlank(client.Email)) {
            listMsgs.add(buildTargetEmail(client.Id, proj.Id, subj, body));
        } else {
            listMsgs.add(buildDirectEmail(to, proj.Id, subj, body));
        }
        return listMsgs;
    }

    /**
     * Builds completion email(s) for the Supervisor.
     * If a Supervisor User with email exists, uses setTargetObjectId,
     * otherwise falls back to a text email field on the Project.
     *
     * @param proj   Project__c record
     * @param client Related Contact (Client__c)
     * @param sup    Supervisor User
     * @param tpls   Container for all templates
     * @return List of SingleEmailMessage for supervisor notification.
     */
    private static List<Messaging.SingleEmailMessage> buildSupervisorEmails(
        Project__c proj, Contact client, User sup, Templates tpls
    ) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tpls == null || tpls.supervisor == null) {
            return listMsgs;
        }

        String fallback = String.valueOf(proj.get('Supervisor_Email_Text_c__c'));
        String to = (sup != null && String.isNotBlank(sup.Email)) ? sup.Email : fallback;
        if (String.isBlank(to)) {
            return listMsgs;
        }

        String subj = replaceVars(tpls.supervisor.Subject,  proj, client, sup, null);
        String body = replaceVars(tpls.supervisor.HtmlValue, proj, client, sup, null);

        if (sup != null && String.isNotBlank(sup.Email)) {
            listMsgs.add(buildTargetEmail(sup.Id, proj.Id, subj, body));
        } else {
            listMsgs.add(buildDirectEmail(to, proj.Id, subj, body));
        }
        return listMsgs;
    }

    /**
     * Builds completion email(s) for role-based Managers (UserRole.Name LIKE '%Manager%').
     * Each manager receives a personalized email where {{{ManagerName}}} is substituted.
     *
     * @param proj         Project__c record
     * @param client       Related Contact (Client__c)
     * @param sup          Supervisor User
     * @param tpls         Container for all templates
     * @param roleManagers List of manager Users filtered by role
     * @return List of SingleEmailMessage for manager notifications.
     */
    private static List<Messaging.SingleEmailMessage> buildRoleManagerEmails(
        Project__c proj, Contact client, User sup, Templates tpls, List<User> roleManagers
    ) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tpls == null || tpls.manager == null || roleManagers == null || roleManagers.isEmpty()) {
            return listMsgs;
        }

        for (User mgr : roleManagers) {
            if (mgr == null || String.isBlank(mgr.Email)) {
                continue;
            }
            String mgrName = String.isNotBlank(mgr.Name) ? mgr.Name : 'Manager';
            String subj    = replaceVars(tpls.manager.Subject,  proj, client, sup, mgrName);
            String body    = replaceVars(tpls.manager.HtmlValue, proj, client, sup, mgrName);
            listMsgs.add(buildDirectEmail(mgr.Email.trim(), proj.Id, subj, body));
        }
        return listMsgs;
    }

    /**
     * Builds completion email(s) for general management/enrollment members,
     * using a CSV list of addresses from a label (or other source).
     *
     * @param proj   Project__c record
     * @param client Related Contact (Client__c)
     * @param sup    Supervisor User
     * @param tmpl   EmailTemplate used for these recipients
     * @param csv    Comma-separated list of email addresses
     * @return List of SingleEmailMessage for all CSV recipients.
     */
    private static List<Messaging.SingleEmailMessage> buildCsvLabelEmails(
        Project__c proj,
        Contact client,
        User sup,
        EmailTemplate tmpl,
        String csv
    ) {
        if (tmpl == null || String.isBlank(csv)) {
            return new List<Messaging.SingleEmailMessage>();
        }
        return buildPerRecipientFromCsv(tmpl, proj, client, sup, csv);
    }

    // =========================================================================
    // Query helpers (Contact / User / Role-based User)
    // =========================================================================

    /**
     * Retrieves all Clients (Contact) referenced by the given Projects.
     *
     * @param projects List of Project__c records
     * @return Map<Id, Contact> keyed by Contact Id.
     *
     * PMD.ApexCRUDViolation:
     *  - Read-only query on Contact with minimal fields and wrapped in try/catch.
     *    Sharing and CRUD are enforced at a higher layer; hence class-level suppress.
     */
    private static Map<Id, Contact> getClientContacts(List<Project__c> projects) {
        Set<Id> ids = new Set<Id>();
        for (Project__c p : projects) {
            if (p.Client__c != null) {
                ids.add(p.Client__c);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, Contact>();
        }
        try {
            return new Map<Id, Contact>([SELECT Id, Name, Email
                FROM Contact WHERE Id IN :ids]);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fetch Contacts failed: ' + e.getMessage());
            return new Map<Id, Contact>();
        }
    }

    /**
     * Retrieves all Supervisor Users referenced by the given Projects.
     *
     * @param projects List of Project__c records
     * @return Map<Id, User> keyed by User Id.
     */
    private static Map<Id, User> getSupervisorUsers(List<Project__c> projects) {
        Set<Id> ids = new Set<Id>();
        for (Project__c p : projects) {
            if (p.Supervisor_User__c != null) {
                ids.add(p.Supervisor_User__c);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, User>();
        }
        try {
            return new Map<Id, User>([SELECT Id, Name, Email FROM User WHERE Id IN :ids]);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fetch Users failed: ' + e.getMessage());
            return new Map<Id, User>();
        }
    }

    /**
     * Retrieves active Users with a role name containing 'Manager'
     * to be used for manager notifications and {{{ManagerName}}} token.
     *
     * @return List<User> with role-based manager users.
     */
    private static List<User> getManagersByRole() {
        try {
            return [SELECT Id, Name, Email FROM User WHERE IsActive = true
                  AND Email != null AND UserRole.Name LIKE '%Manager%'];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fetch role managers failed: ' + e.getMessage());
            return new List<User>();
        }
    }

    // =========================================================================
    // Email primitive builders
    // =========================================================================

    /**
     * Builds a SingleEmailMessage using setTargetObjectId (for Contacts/Users),
     * attaching the project via setWhatId and using HTML body.
     *
     * @param targetId Id of Contact/User
     * @param whatId   Project__c Id
     * @param subject  Email subject
     * @param body     HTML email body
     * @return Messaging.SingleEmailMessage ready to send.
     */
    private static Messaging.SingleEmailMessage buildTargetEmail(Id targetId, Id whatId, String subject, String body) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setTargetObjectId(targetId);
        m.setWhatId(whatId);
        m.setSubject(subject);
        m.setHtmlBody(body);
        m.setSaveAsActivity(false);
        m.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
        return m;
    }

    /**
     * Builds a SingleEmailMessage using direct email addresses
     * instead of a target object; used when Contact/User records
     * are not available.
     *
     * @param toAddress Recipient email address
     * @param whatId    Project__c Id
     * @param subject   Email subject
     * @param body      HTML email body
     * @return Messaging.SingleEmailMessage ready to send.
     */
    private static Messaging.SingleEmailMessage buildDirectEmail(String toAddress, Id whatId, String subject, String body) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ toAddress });
        m.setWhatId(whatId);
        m.setSubject(subject);
        m.setHtmlBody(body);
        m.setSaveAsActivity(false);
        m.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
        return m;
    }

    /**
     * Builds a dedicated email per CSV recipient, each personalized
     * with {{{ManagerName}}} based on the email address (local-part).
     *
     * @param tmpl    EmailTemplate used for subject/body (with tokens)
     * @param proj    Project__c record
     * @param contact Related Contact (Client__c)
     * @param sup     Supervisor User
     * @param csv     Comma-separated list of email addresses
     * @return List of SingleEmailMessage, one per CSV address.
     */
    private static List<Messaging.SingleEmailMessage> buildPerRecipientFromCsv(
        EmailTemplate tmpl,
        Project__c proj,
        Contact contact,
        User sup,
        String csv
    ) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tmpl == null || String.isBlank(csv)) {
            return listMsgs;
        }

        List<String> emails = csv.split(',');
        for (String raw : emails) {
            String addr = (raw == null) ? null : raw.trim();
            if (String.isBlank(addr)) {
                continue;
            }
            String display = inferDisplayNameFromEmail(addr); // "jane.doe@x.com" → "Jane Doe"
            String subj    = replaceVars(tmpl.Subject,  proj, contact, sup, display);
            String body    = replaceVars(tmpl.HtmlValue, proj, contact, sup, display);
            listMsgs.add(buildDirectEmail(addr, proj.Id, subj, body));
        }
        return listMsgs;
    }

    // =========================================================================
    // Template token replacement & utility methods
    // =========================================================================

    /**
     * Replaces all {{{...}}} tokens in the given string with values
     * from Project, Contact, Supervisor, and an optional ManagerName.
     *
     * Tokens handled:
     *  - {{{Project__c.Name}}}
     *  - {{{Project__c.Project_Code__c}}}
     *  - {{{Project__c.Status__c}}}
     *  - {{{Project__c.Type_Of_Project__c}}}
     *  - {{{Project__c.Project_Scope__c}}}
     *  - {{{Project__r.Client__r.Name}}}
     *  - {{{Project__r.Supervisor_User__r.Name}}}
     *  - {{{ManagerName}}}
     *
     * @param input       Template string (subject/body) to be processed.
     * @param proj        Project__c
     * @param contact     Contact (Client)
     * @param sup         Supervisor User
     * @param managerName Optional ManagerName for manager templates.
     * @return String with tokens replaced; never null (returns empty string if input is blank).
     */
    private static String replaceVars(String input, Project__c proj, Contact contact,
        User sup, String managerName ) 
    {
        if (String.isBlank(input)) {
            return '';
        }
        String outStr = input
            .replace('{{{Project__c.Name}}}',                   safe(proj != null ? proj.Name : null))
            .replace('{{{Project__c.Project_Code__c}}}',        safe(proj != null ? proj.Project_Code__c : null))
            .replace('{{{Project__c.Status__c}}}',              safe(proj != null ? proj.Status__c : null))
            .replace('{{{Project__c.Type_Of_Project__c}}}',     safe(proj != null ? proj.Type_Of_Project__c : null))
            .replace('{{{Project__c.Project_Scope__c}}}',       safe(proj != null ? proj.Project_Scope__c : null))
            .replace('{{{Project__r.Client__r.Name}}}',         safe(contact != null ? contact.Name : null))
            .replace('{{{Project__r.Supervisor_User__r.Name}}}', safe(sup != null ? sup.Name : null));

        // Personalization for manager template
        outStr = outStr.replace('{{{ManagerName}}}', safe(managerName));
        return outStr;
    }

    /**
     * Fetches a single EmailTemplate by its DeveloperName.
     * Returns null if not found or if query fails.
     *
     * @param developerName DeveloperName of the EmailTemplate
     * @return EmailTemplate or null if not found.
     */
    private static EmailTemplate fetchEmailTemplate(String developerName) {
        try {
            List<EmailTemplate> t = [SELECT Id, Subject, HtmlValue
                FROM EmailTemplate WHERE DeveloperName = :developerName LIMIT 1];
            return t.isEmpty() ? null : t[0];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fetch template failed: ' + developerName + ' | ' + e.getMessage());
            return null;
        }
    }

    /**
     * Retrieves the OrgWideEmailAddress Id based on DEFAULT_OWD_EMAIL label.
     * Returns null if not found or on error.
     *
     * @return OrgWideEmailAddress Id or null.
     */
    private static Id getOrgWideEmailAddressId() {
        try {
            List<OrgWideEmailAddress> o = [SELECT Id FROM OrgWideEmailAddress
                WHERE Address = :DEFAULT_OWD_EMAIL LIMIT 1];
            return o.isEmpty() ? null : o[0].Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fetch OWD failed: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Derives a friendly display name from an email address.
     * Example:
     *  - "jane.doe@company.com" -> "Jane Doe"
     *
     * @param emailAddr Email address string
     * @return Friendly name or "Manager" as a safe fallback.
     */
    private static String inferDisplayNameFromEmail(String emailAddr) {
        if (String.isBlank(emailAddr) || !emailAddr.contains('@')) {
            return 'Manager';
        }
        String local = emailAddr.substring(0, emailAddr.indexOf('@'));
        local = local.replace('.', ' ').replace('_', ' ').trim();
        if (String.isBlank(local)) {
            return 'Manager';
        }
        List<String> parts = local.split('\\s+');
        List<String> caps  = new List<String>();
        for (String p : parts) {
            if (String.isBlank(p)) {
                continue;
            }
            String first = p.substring(0, 1).toUpperCase();
            String rest  = (p.length() > 1) ? p.substring(1).toLowerCase() : '';
            caps.add(first + rest);
        }
        return caps.isEmpty() ? 'Manager' : String.join(caps, ' ');
    }

    /**
     * Simple null/blank-safe helper.
     *
     * @param v String value
     * @return v if non-blank, otherwise an empty string.
     */
    private static String safe(String v) {
        return String.isNotBlank(v) ? v : '';
    }
}
