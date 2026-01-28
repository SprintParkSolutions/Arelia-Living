/**
 * @description
 * Handler class for operations related to Project__c object,
 * including assigning project codes and sending email notifications.
 *
 * @author Arelia team
 */
@SuppressWarnings('PMD.ApexCRUDViolation, PMD.ExcessivePublicCount, PMD.StdCyclomaticComplexity, PMD.CyclomaticComplexity')
public without sharing class ProjectTriggerHandler {

    // Configuration Variables
    @TestVisible private static String clientTemplateName = Label.Arelia_Living_Client_Project_Notification;
    @TestVisible private static String supervisorTemplateName = Label.Arelia_Living_Supervisor_Project_Notification;
    @TestVisible private static String managerTemplateName = Label.Arelia_Living_Sending_Project_Create_Information_to_Manager;
    @TestVisible private static String mgmtTemplateName = Label.Arelia_Living_Sending_Project_Create_Information_to_Management;
    @TestVisible private static String enrollmentTemplateName = Label.Arelia_Living_Sending_Project_Create_Information_to_Enrollment;

    @TestVisible private static String defaultOwdEmail = Label.Arelia_OWD;
    @TestVisible private static String mgmtEmailListLabel = Label.Arelia_Living_Enrollment_Members;

    /**
     * @description Assigns unique codes to Project records.
     * @param projects List of Project__c records.
     */
    public static void assignProjectCodes(List<Project__c> projects) {
        if (projects == null) {
            return;
        }

        for (Project__c proj : projects) {
            // Coverage: Skip if null or already has code
            if (proj == null || String.isNotBlank(proj.Project_Code__c)) {
                continue;
            }

            String prefix = 'AL-';
            String timePart = String.valueOf(Datetime.now().getTime()).right(6);
            String randomPart = String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 4);
            proj.Project_Code__c = prefix + timePart + '-' + randomPart;
        }
    }

    /**
     * @description Sends email notifications to various stakeholders.
     * @param projects List of Project__c records.
     */
    public static void sendProjectApprovedEmail(List<Project__c> projects) {
        if (projects == null || projects.isEmpty()) {
            return;
        }

        // Delegate to Orchestrator to handle complexity and state
        EmailOrchestrator orchestrator = new EmailOrchestrator();
        orchestrator.loadData(projects);

        List<Messaging.SingleEmailMessage> allEmails = new List<Messaging.SingleEmailMessage>();

        for (Project__c proj : projects) {
            if (proj == null) {
                continue;
            }
            allEmails.addAll(orchestrator.processProject(proj));
        }

        if (!allEmails.isEmpty()) {
            Messaging.sendEmail(allEmails);
        }
    }

    // ============================================================================
    // Inner Class: EmailOrchestrator
    // Handles data fetching and email construction
    // ============================================================================
    private without sharing class EmailOrchestrator {
        private Map<Id, Contact> contactMap;
        private Map<Id, User> userMap;
        private EmailTemplate clientTmpl;
        private EmailTemplate supTmpl;
        private EmailTemplate managerTmpl;
        private EmailTemplate mgmtTmpl;
        private EmailTemplate enrollmentTmpl;
        private Id owdId;

        public void loadData(List<Project__c> projects) {
            this.contactMap = getClientContacts(projects);
            this.userMap = getSupervisorUsers(projects);
            this.owdId = getOrgWideEmailAddressId();
            
            this.clientTmpl = fetchEmailTemplate(clientTemplateName);
            this.supTmpl = fetchEmailTemplate(supervisorTemplateName);
            this.managerTmpl = fetchEmailTemplate(managerTemplateName);
            this.mgmtTmpl = fetchEmailTemplate(mgmtTemplateName);
            this.enrollmentTmpl = fetchEmailTemplate(enrollmentTemplateName);
        }

        public List<Messaging.SingleEmailMessage> processProject(Project__c proj) {
            List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
            
            Contact client = contactMap.get(proj.Client__c);
            User sup = userMap.get(proj.Supervisor_User__c);
            MergeContext mCtx = new MergeContext(proj, client, sup);

            // 1. Individual Emails
            // Coverage note: If sup is null, buildSingleEmail returns null, handled by addIfNotNull
            addIfNotNull(mails, buildSingleEmail(supTmpl, (sup != null ? sup.Id : null), mCtx));
            addIfNotNull(mails, buildSingleEmail(clientTmpl, (client != null ? client.Id : null), mCtx));

            // 2. Group Emails
            mails.addAll(buildGroupEmails(mgmtTmpl, mgmtEmailListLabel, mCtx));

            String managerEmails = String.join(getManagerEmailsByRole(), ',');
            mails.addAll(buildGroupEmails(managerTmpl, managerEmails, mCtx));

            String enrollmentEmails = String.join(getEnrollmentEmailsByRole(), ',');
            mails.addAll(buildGroupEmails(enrollmentTmpl, enrollmentEmails, mCtx));

            return mails;
        }

        private void addIfNotNull(List<Messaging.SingleEmailMessage> listToAddTo, Messaging.SingleEmailMessage mail) {
            if (mail != null) {
                listToAddTo.add(mail);
            }
        }

        private Messaging.SingleEmailMessage buildSingleEmail(EmailTemplate tmpl, Id targetId, MergeContext mCtx) {
            if (tmpl == null || targetId == null) {
                return null;
            }
            return createEmail(new List<String>(), targetId, mCtx.mergeText(tmpl.Subject, null), mCtx.mergeText(tmpl.HtmlValue, null));
        }

        private List<Messaging.SingleEmailMessage> buildGroupEmails(EmailTemplate tmpl, String labelEmails, MergeContext mCtx) {
            List<Messaging.SingleEmailMessage> result = new List<Messaging.SingleEmailMessage>();
            if (tmpl == null || String.isBlank(labelEmails)) {
                return result;
            }

            List<String> emailList = splitEmailString(labelEmails);
            if (emailList.isEmpty()) {
                return result;
            }

            Boolean needsManagerName = (tmpl.Subject != null && tmpl.Subject.contains('{{{ManagerName}}}')) ||
                                       (tmpl.HtmlValue != null && tmpl.HtmlValue.contains('{{{ManagerName}}}'));

            if (needsManagerName) {
                Map<String, String> emailToName = resolveUserNamesByEmail(emailList);
                for (String addr : emailList) {
                    if (String.isBlank(addr)) { continue; }
                    String mgrName = emailToName.containsKey(addr) ? emailToName.get(addr) : nameFromEmail(addr);
                    result.add(createEmail(new List<String>{ addr }, null, mCtx.mergeText(tmpl.Subject, mgrName), mCtx.mergeText(tmpl.HtmlValue, mgrName)));
                }
            } else {
                result.add(createEmail(emailList, null, mCtx.mergeText(tmpl.Subject, null), mCtx.mergeText(tmpl.HtmlValue, null)));
            }
            return result;
        }

        private Messaging.SingleEmailMessage createEmail(List<String> toAddresses, Id targetObjId, String subject, String body) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            if (targetObjId != null) {
                email.setTargetObjectId(targetObjId);
                email.setWhatId(targetObjId); 
            } else {
                email.setToAddresses(toAddresses);
            }
            email.setSubject(subject);
            email.setHtmlBody(body);
            email.setSaveAsActivity(false);
            if (this.owdId != null) {
                email.setOrgWideEmailAddressId(this.owdId);
            }
            return email;
        }

        // Helpers
        private Map<Id, Contact> getClientContacts(List<Project__c> projects) {
            Set<Id> ids = new Set<Id>();
            for (Project__c p : projects) { if (p != null && p.Client__c != null) ids.add(p.Client__c); }
            if (ids.isEmpty()) { return new Map<Id, Contact>(); }
            return new Map<Id, Contact>([SELECT Id, Name, Email FROM Contact WHERE Id IN :ids]);
        }

        private Map<Id, User> getSupervisorUsers(List<Project__c> projects) {
            Set<Id> ids = new Set<Id>();
            for (Project__c p : projects) { if (p != null && p.Supervisor_User__c != null) ids.add(p.Supervisor_User__c); }
            if (ids.isEmpty()) { return new Map<Id, User>(); }
            return new Map<Id, User>([SELECT Id, Name, Email FROM User WHERE Id IN :ids]);
        }

        private EmailTemplate fetchEmailTemplate(String name) {
            try {
                List<EmailTemplate> templates = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :name LIMIT 1];
                return templates.isEmpty() ? null : templates[0];
            } catch (Exception e) { return null; }
        }

        private Id getOrgWideEmailAddressId() {
            try {
                if (String.isBlank(defaultOwdEmail)) { return null; }
                List<OrgWideEmailAddress> addresses = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :defaultOwdEmail LIMIT 1];
                return addresses.isEmpty() ? null : addresses[0].Id;
            } catch (Exception e) { return null; }
        }

        private List<String> splitEmailString(String rawList) {
            List<String> res = new List<String>();
            if (String.isNotBlank(rawList)) {
                for (String raw : rawList.split(',')) { if (String.isNotBlank(raw)) res.add(raw.trim()); }
            }
            return res;
        }
    }

    // ============================================================================
    // Inner Class: MergeContext
    // ============================================================================
    private inherited sharing class MergeContext {
        private String safeProjName;
        private String safeProjCode;
        private String safeProjStatus;
        private String safeProjType;
        private String safeProjScope;
        private String safeClientName;
        private String safeProjReqType;
        private String safeSupName;

        public MergeContext(Project__c proj, Contact client, User sup) {
            this.safeProjName = safe(proj != null ? proj.Name : '');
            this.safeProjCode = safe(proj != null ? proj.Project_Code__c : '');
            this.safeProjStatus = safe(proj != null ? proj.Status__c : '');
            this.safeProjType = safe(proj != null ? proj.Type_Of_Project__c : '');
            this.safeProjScope = safe(proj != null ? proj.Project_Scope__c : '');
            this.safeProjReqType = safe(proj != null ? proj.Project_Request_Quotation_Type__c : '');
            this.safeClientName = safe(client != null ? client.Name : '');
            this.safeSupName = safe(sup != null ? sup.Name : '');
        }

        public String mergeText(String input, String managerName) {
            String base = (input == null) ? '' : input;
            base = base.replace('{{{Project__c.Name}}}', safeProjName)
                       .replace('{{{Project__c.Project_Code__c}}}', safeProjCode)
                       .replace('{{{Project__c.Status__c}}}', safeProjStatus)
                       .replace('{{{Project__c.Type_Of_Project__c}}}', safeProjType)
                       .replace('{{{Project__c.Project_Scope__c}}}', safeProjScope)
                       .replace('{{{Project__r.Client__r.Name}}}', safeClientName)
                       .replace('{{{Project__c.Project_Request_Quotation_Type__c}}}', safeProjReqType)
                       .replace('{{{Project__r.Supervisor_User__r.Name}}}', safeSupName);
            
            if (base.contains('{{{ManagerName}}}')) {
                base = base.replace('{{{ManagerName}}}', safe(managerName));
            }
            return base;
        }

        private String safe(String value) { return String.isNotBlank(value) ? value : ''; }
    }

    // ============================================================================
    // Static Helpers
    // ============================================================================
    private static Map<String, String> resolveUserNamesByEmail(List<String> emails) {
        Map<String, String> m = new Map<String, String>();
        if (emails == null || emails.isEmpty()) { return m; }
        for (User u : [SELECT Name, Email FROM User WHERE IsActive = true AND Email IN :emails]) {
            if (u != null && String.isNotBlank(u.Email)) { m.put(u.Email.trim(), u.Name); }
        }
        return m;
    }

    private static String nameFromEmail(String email) {
        if (String.isBlank(email)) { return ''; }
        String local = email.split('@')[0];
        local = local.replace('.', ' ').replace('_', ' ').replace('-', ' ');
        List<String> parts = local.split(' ');
        List<String> pretty = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) { pretty.add(p.substring(0, 1).toUpperCase() + (p.length() > 1 ? p.substring(1).toLowerCase() : '')); }
        }
        return String.join(pretty, ' ');
    }

    private static List<String> getManagerEmailsByRole() {
        List<String> res = new List<String>();
        for (User u : [SELECT Email FROM User WHERE UserRole.Name LIKE '%Manager%' AND IsActive = true AND Email != null]) { res.add(u.Email.trim()); }
        return res;
    }

    private static List<String> getEnrollmentEmailsByRole() {
        List<String> res = new List<String>();
        for (User u : [SELECT Email FROM User WHERE UserRole.Name LIKE '%Enrollment%' AND IsActive = true AND Email != null]) { res.add(u.Email.trim()); }
        return res;
    }
}