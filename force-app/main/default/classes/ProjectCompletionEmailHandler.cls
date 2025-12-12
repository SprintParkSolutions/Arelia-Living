//without manager name population backup code


// public without sharing class ProjectCompletionEmailHandler {
//     // Preferred (Completed) templates
//     private static final String CLIENT_TPL_COMPLETED     = 'Client_Project_Completed_Notification';
//     private static final String SUPERVISOR_TPL_COMPLETED = 'Supervisor_Project_Completed_Notification';
//     private static final String MANAGER_TPL_COMPLETED    = 'Sending_Project_Completed_Information_to_Manager';
//     private static final String MGMT_TPL                 = 'Sending_Project_Completed_Information_to_Management';
//     private static final String ENROLL_TPL               = 'Sending_Project_Completed_Information_to_Enrollment';

//     // Labels
//     private static final String DEFAULT_OWD_EMAIL = System.Label.Arelia_OWD;
//     private static final String MGMT_LABEL_CSV    = System.Label.Management_Email_Addresses;
//     private static final String ENROLL_LABEL_CSV = System.Label.Enrollment_Email_Addresses;

//     // =========================================================================
//     // Called from trigger.afterUpdate: detect transition to Completed @ 100%
//     // =========================================================================
//     public static void handleAfterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
//         if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) return;

//         List<Project__c> justCompleted = new List<Project__c>();
//         for (Project__c n : newList) {
//             Project__c o = oldMap.get(n.Id);
//             if (o == null) continue;

//             Boolean nowCompleted = (n.Status__c == 'Completed' && n.Project_Completion_Status__c == 100);
//             Boolean wasCompleted = (o.Status__c == 'Completed' && o.Project_Completion_Status__c == 100);

//             if (nowCompleted && !wasCompleted) {
//                 justCompleted.add(n);
//             }
//         }

//         if (!justCompleted.isEmpty()) {
//             sendProjectApprovedEmail(justCompleted);
//         }
//     }

//     /**
//      * @description
//      * Sends email notifications to:
//      * - The assigned Supervisor (User.Email or Supervisor_Email_Text_c__c)
//      * - The Client (Contact.Email or Client_Email__c)
//      * - Managers (role users) + Manager label only (Management_Email_Addresses)
//      * - Enrollment users (role users)
//      */
//     public static void sendProjectApprovedEmail(List<Project__c> projects) {
//         if (projects == null || projects.isEmpty()) { return; }

//         try {
//             Map<Id, Contact> contactMap = getClientContacts(projects);
//             Map<Id, User>    userMap    = getSupervisorUsers(projects);

//             EmailTemplate clientTmpl     = fetchEmailTemplate(CLIENT_TPL_COMPLETED);
//             EmailTemplate supTmpl        = fetchEmailTemplate(SUPERVISOR_TPL_COMPLETED);
//             EmailTemplate managerTmpl    = fetchEmailTemplate(MANAGER_TPL_COMPLETED);
//             EmailTemplate mgmtTmpl       = fetchEmailTemplate(MGMT_TPL);
//             EmailTemplate enrollmentTmpl = fetchEmailTemplate(ENROLL_TPL);

//             List<Messaging.SingleEmailMessage> allEmails = new List<Messaging.SingleEmailMessage>();

//             for (Project__c proj : projects) {
//                 Contact client = contactMap.get(proj.Client__c);
//                 User    sup    = userMap.get(proj.Supervisor_User__c);

//                 // ---------------- Client (Customer) ----------------
//                 if (clientTmpl != null) {
//                     // prefer Contact.Email; else fall back to formula Client_Email__c on Project__c
//                     String clientEmail = (client != null && !String.isBlank(client.Email))
//                         ? client.Email
//                         : String.valueOf(proj.get('Client_Email__c'));

//                     if (!String.isBlank(clientEmail)) {
//                         String subj = replaceTemplateVars(clientTmpl.Subject,  proj, client, sup);
//                         String body = replaceTemplateVars(clientTmpl.HtmlValue, proj, client, sup);

//                         if (client != null && !String.isBlank(client.Email)) {
//                             // Send to Contact directly (TargetObjectId)
//                             allEmails.add(buildEmailMessage(client.Id, proj.Id, subj, body));
//                         } else {
//                             // Send to explicit email address (formula)
//                             allEmails.add(buildDirectEmailMessage(clientEmail, proj.Id, subj, body));
//                         }
//                     }
//                 }

//                 // ---------------- Supervisor ----------------
//                 if (supTmpl != null) {
//                     // prefer User.Email; else fall back to formula Supervisor_Email_Text_c__c on Project__c
//                     String supEmail = (sup != null && !String.isBlank(sup.Email))
//                         ? sup.Email
//                         : String.valueOf(proj.get('Supervisor_Email_Text_c__c'));

//                     if (!String.isBlank(supEmail)) {
//                         String subj = replaceTemplateVars(supTmpl.Subject,  proj, client, sup);
//                         String body = replaceTemplateVars(supTmpl.HtmlValue, proj, client, sup);

//                         if (sup != null && !String.isBlank(sup.Email)) {
//                             allEmails.add(buildEmailMessage(sup.Id, proj.Id, subj, body));
//                         } else {
//                             allEmails.add(buildDirectEmailMessage(supEmail, proj.Id, subj, body));
//                         }
//                     }
//                 }

//                 // ---------------- Managers (role) ---------
//                 allEmails.addAll(buildGroupEmails(managerTmpl, proj, client, sup, String.join(getManagerEmailsByRole(), ',')));

//                //-------  Manager label + Enrollment Label  ----------------
//                 allEmails.addAll(buildGroupEmails(mgmtTmpl, proj, client, sup, MGMT_LABEL_CSV));
//                 //allEmails.addAll(buildGroupEmails(enrollmentTmpl, proj, client, sup, ENROLL_LABEL_CSV));

//                 // ---------------- Enrollment (role users only) ----------------
//                 allEmails.addAll(buildGroupEmails(enrollmentTmpl, proj, client, sup, String.join(getEnrollmentEmailsByRole(), ',')));
//             }

//             if (!allEmails.isEmpty()) {
//                 Messaging.sendEmail(allEmails);
//             }
//         } catch (Exception e) {
//             System.debug(LoggingLevel.ERROR, 'Error sending emails for Projects: ' + e.getMessage());
//         }
//     }

//     // ---------- helpers you already had (small tweaks) ----------

//     private static Map<Id, Contact> getClientContacts(List<Project__c> projects) {
//         Set<Id> contactIds = new Set<Id>();
//         for (Project__c proj : projects) {
//             if (proj.Client__c != null) { contactIds.add(proj.Client__c); }
//         }
//         if (contactIds.isEmpty()) { return new Map<Id, Contact>(); }

//         try {
//             return new Map<Id, Contact>([
//                 SELECT Id, Name, Email
//                 FROM Contact
//                 WHERE Id IN :contactIds
//             ]);
//         } catch (Exception e) {
//             System.debug(LoggingLevel.ERROR, 'Error fetching Contacts: ' + e.getMessage());
//             return new Map<Id, Contact>();
//         }
//     }

//     private static Map<Id, User> getSupervisorUsers(List<Project__c> projects) {
//         Set<Id> userIds = new Set<Id>();
//         for (Project__c proj : projects) {
//             if (proj.Supervisor_User__c != null) { userIds.add(proj.Supervisor_User__c); }
//         }
//         if (userIds.isEmpty()) { return new Map<Id, User>(); }

//         try {
//             return new Map<Id, User>([
//                 SELECT Id, Name, Email
//                 FROM User
//                 WHERE Id IN :userIds
//             ]);
//         } catch (Exception e) {
//             System.debug(LoggingLevel.ERROR, 'Error fetching Users: ' + e.getMessage());
//             return new Map<Id, User>();
//         }
//     }

//     /**
//      * Builds emails for CSV recipients using the template's subject/body with simple replacements.
//      * Note: This does NOT perform SFDC merge; it uses your replaceTemplateVars() output.
//      */
//     private static List<Messaging.SingleEmailMessage> buildGroupEmails(
//         EmailTemplate tmpl, Project__c proj, Contact contact, User sup, String labelEmails
//     ) {
//         List<Messaging.SingleEmailMessage> result = new List<Messaging.SingleEmailMessage>();
//         if (tmpl == null || String.isBlank(labelEmails)) { return result; }

//         try {
//             List<String> emailList = labelEmails.split(',');
//             if (emailList.isEmpty()) { return result; }

//             String subj = replaceTemplateVars(tmpl.Subject,  proj, contact, sup);
//             String body = replaceTemplateVars(tmpl.HtmlValue, proj, contact, sup);

//             Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
//             email.setToAddresses(emailList);
//             email.setSubject(subj);
//             email.setHtmlBody(body);
//             email.setSaveAsActivity(false);
//             email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
//             result.add(email);
//         } catch (Exception e) {
//             System.debug(LoggingLevel.ERROR, 'Error building group email: ' + e.getMessage());
//         }
//         return result;
//     }

//     /** Send to a specific Contact/User target (TargetObjectId pattern). */
//     private static Messaging.SingleEmailMessage buildEmailMessage(Id targetId, Id whatId, String subject, String body) {
//         Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
//         email.setTargetObjectId(targetId);
//         email.setWhatId(whatId);
//         email.setSubject(subject);
//         email.setHtmlBody(body);
//         email.setSaveAsActivity(false);
//         email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
//         return email;
//     }

//     /** Send to a raw email address (used for formula fallback). */
//     private static Messaging.SingleEmailMessage buildDirectEmailMessage(String toAddress, Id whatId, String subject, String body) {
//         Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
//         email.setToAddresses(new List<String>{ toAddress });
//         email.setWhatId(whatId);
//         email.setSubject(subject);
//         email.setHtmlBody(body);
//         email.setSaveAsActivity(false);
//         email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
//         return email;
//     }

//     /** Your simple token replacer. Make sure your templates use the same tokens. */
//     private static String replaceTemplateVars(String input, Project__c proj, Contact contact, User sup) {
//         if (String.isBlank(input)) return '';
//         return input
//             .replace('{{{Project__c.Name}}}',               safe(proj.Name))
//             .replace('{{{Project__c.Project_Code__c}}}',    safe(proj.Project_Code__c))
//             .replace('{{{Project__c.Status__c}}}',          safe(proj.Status__c))
//             .replace('{{{Project__c.Type_Of_Project__c}}}', safe(proj.Type_Of_Project__c))
//             .replace('{{{Project__c.Project_Scope__c}}}',   safe(proj.Project_Scope__c))
//             .replace('{{{Project__r.Client__r.Name}}}',     safe(contact != null ? contact.Name : ''))
//             .replace('{{{Project__r.Supervisor_User__r.Name}}}', safe(sup != null ? sup.Name : ''));
//     }

//     private static EmailTemplate fetchEmailTemplate(String name) {
//         try {
//             List<EmailTemplate> templates = [
//                 SELECT Id, Subject, HtmlValue
//                 FROM EmailTemplate
//                 WHERE DeveloperName = :name
//                 LIMIT 1
//             ];
//             return templates.isEmpty() ? null : templates[0];
//         } catch (Exception e) {
//             System.debug(LoggingLevel.ERROR, 'Error fetching EmailTemplate: ' + name + ' | ' + e.getMessage());
//             return null;
//         }
//     }

//     private static Id getOrgWideEmailAddressId() {
//         try {
//             List<OrgWideEmailAddress> addresses = [
//                 SELECT Id
//                 FROM OrgWideEmailAddress
//                 WHERE Address = :DEFAULT_OWD_EMAIL
//                 LIMIT 1
//             ];
//             return addresses.isEmpty() ? null : addresses[0].Id;
//         } catch (Exception e) {
//             System.debug(LoggingLevel.ERROR, 'Error fetching OrgWideEmailAddress: ' + e.getMessage());
//             return null;
//         }
//     }

//     private static String safe(String value) {
//         return String.isNotBlank(value) ? value : '';
//     }

//     private static List<String> getManagerEmailsByRole() {
//         List<String> managerEmails = new List<String>();
//         for (User u : [
//             SELECT Email
//             FROM User
//             WHERE UserRole.Name LIKE '%Manager%'
//               AND IsActive = true
//               AND Email != null
//         ]) managerEmails.add(u.Email.trim());
//         return managerEmails;
//     }

//     private static List<String> getEnrollmentEmailsByRole() {
//         List<String> enrollmentEmails = new List<String>();
//         for (User u : [
//             SELECT Email
//             FROM User
//             WHERE UserRole.Name LIKE '%Enrollment%'
//               AND IsActive = true
//               AND Email != null
//         ]) enrollmentEmails.add(u.Email.trim());
//         return enrollmentEmails;
//     }
// }








public without sharing class ProjectCompletionEmailHandler {
    // ---------- Template API Names ----------
    private static final String CLIENT_TPL_COMPLETED     = 'Client_Project_Completed_Notification';
    private static final String SUPERVISOR_TPL_COMPLETED = 'Supervisor_Project_Completed_Notification';
    private static final String MANAGER_TPL_COMPLETED    = 'Sending_Project_Completed_Information_to_Manager';
    private static final String MGMT_TPL                 = 'Sending_Project_Completed_Information_to_Management';
    private static final String ENROLL_TPL               = 'Sending_Project_Completed_Information_to_Enrollment';

    // ---------- Custom Labels ----------
    private static final String DEFAULT_OWD_EMAIL = System.Label.Arelia_OWD;
    private static final String MGMT_LABEL_CSV    = System.Label.Management_Email_Addresses;
    private static final String ENROLL_LABEL_CSV  = System.Label.Enrollment_Email_Addresses;

    // =========================================================================
    // Entry from after update trigger (only when project flips to Completed @ 100)
    // =========================================================================
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
            sendProjectApprovedEmail(justCompleted);
        }
    }

    // ========= Orchestrator (now tiny/low-complexity) =========
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

                outbox.addAll(buildClientEmails(proj, client, sup, tpls));
                outbox.addAll(buildSupervisorEmails(proj, client, sup, tpls));
                outbox.addAll(buildRoleManagerEmails(proj, client, sup, tpls, roleManagers));
                outbox.addAll(buildCsvLabelEmails(proj, client, sup, tpls.management, MGMT_LABEL_CSV));
                outbox.addAll(buildCsvLabelEmails(proj, client, sup, tpls.enrollment, ENROLL_LABEL_CSV));
            }

            if (!outbox.isEmpty()) {
                Messaging.sendEmail(outbox);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error sending project completion emails: ' + e.getMessage());
        }
    }

    // ========= Small helpers (each < ~15 CC/NCSS) =========

    private class Templates {
        EmailTemplate client;
        EmailTemplate supervisor;
        EmailTemplate manager;
        EmailTemplate management;
        EmailTemplate enrollment;
    }

    private static Templates loadTemplates() {
        Templates t = new Templates();
        t.client     = fetchEmailTemplate(CLIENT_TPL_COMPLETED);
        t.supervisor = fetchEmailTemplate(SUPERVISOR_TPL_COMPLETED);
        t.manager    = fetchEmailTemplate(MANAGER_TPL_COMPLETED);
        t.management = fetchEmailTemplate(MGMT_TPL);
        t.enrollment = fetchEmailTemplate(ENROLL_TPL);
        return t;
    }

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

    // ----------------------- Query helpers -----------------------
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

    /** Role-based managers to personalize {{{ManagerName}}}. */
    private static List<User> getManagersByRole() {
        try {
            return [SELECT Id, Name, Email FROM User WHERE IsActive = true
                  AND Email != null AND UserRole.Name LIKE '%Manager%'];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Fetch role managers failed: ' + e.getMessage());
            return new List<User>();
        }
    }

    // ----------------------- Build email primitives -----------------------
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

    /** Build one personalized message per CSV address (for {{{ManagerName}}}). */
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

    // ----------------------- Template + tokens -----------------------
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

    private static String safe(String v) {
        return String.isNotBlank(v) ? v : '';
    }
}