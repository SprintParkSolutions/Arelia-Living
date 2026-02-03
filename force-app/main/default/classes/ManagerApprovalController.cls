/**
 * @description Controller for the Manager Approval Portal (LWC).
 * Handles fetching design details and processing approval/rejection logic.
 * * SECURITY NOTE: This class is explicitly 'without sharing' to allow external Managers 
 * (operating as Guest Users) to view specific records via ID and perform updates.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ManagerApprovalController {

    /**
     * @description Wrapper to fix ExcessiveParameterList violation.
     */
    private class ManagerNotificationData {
        public Architecture_Design__c design;
        public String action;
        public String comments;
    }

    // --- 1. Fetch Design Details (GET) ---
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getDesignById(String recordId) {
        System.debug('--- START getDesignById ---');
        
        try {
            Architecture_Design__c design = [
                SELECT Id, Status__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c, 
                       Opportunity__r.Name, Project__r.Name
                FROM Architecture_Design__c 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            
            ContentDocument doc = [
                SELECT Title, FileExtension 
                FROM ContentDocument 
                WHERE Id = :design.Related_File_Id__c 
                LIMIT 1
            ];

            String parentName = (design.Opportunity__r != null) ? design.Opportunity__r.Name : 
                                (design.Project__r != null) ? design.Project__r.Name : 'Unknown Project';

            Map<String, String> result = new Map<String, String>();
            result.put('id', design.Id);
            result.put('title', doc.Title);
            result.put('extension', doc.FileExtension);
            result.put('projectName', parentName);
            result.put('status', design.Manager_Approval__c ? 'Approved' : 'Pending');
            result.put('comments', design.Manager_Comments__c);
            
            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error loading design: ' + e.getMessage());
        }
    }

    // --- 2. Submit Decision (POST) ---
    @AuraEnabled
    public static void submitManagerDecision(String recordId, String action, String comments) {
        System.debug('--- START submitManagerDecision ---');
        
        try {
            Architecture_Design__c design = [
                SELECT Id, Opportunity__c, 
                       Opportunity__r.Name,
                       Opportunity__r.Lead_Name__c, 
                       Opportunity__r.Supervisor_User_Email__c,
                       Opportunity__r.Supervisor_User__r.FirstName, 
                       Opportunity__r.Supervisor_User__r.LastName,  
                       Project__r.Name,
                       Manager_Comments__c 
                FROM Architecture_Design__c 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            
            if (action == 'Approve') {
                design.Manager_Approval__c = true;
                design.Manager_Comments__c = String.isNotBlank(comments) ? comments : 'Approved via Manager Portal';

                if (design.Opportunity__c != null) {
                    Opportunity oppToUpdate = new Opportunity(
                        Id = design.Opportunity__c,
                        Architecture_Manager_Approval__c = true
                    );
                    update oppToUpdate;
                }

            } else if (action == 'Reject') {
                design.Manager_Approval__c = false; 
                design.Manager_Comments__c = comments;
            }
            
            update design;

            sendManagerResponseNotification(design, action, design.Manager_Comments__c);

        } catch (Exception e) { 
            System.debug('ERROR in submitManagerDecision: ' + e.getMessage());
            throw new AuraHandledException('Error submitting decision: ' + e.getMessage()); 
        }
    }

    // --- 3. REFACTORED NOTIFICATION LOGIC ---

    private static void sendManagerResponseNotification(Architecture_Design__c design, String action, String comments) {
        try {
            List<String> toAddresses = getManagerRecipients(design);
            if (toAddresses.isEmpty()) {
                return;
            }

            String templateName = Label.Manager_Response_Notification_Template;
            
            EmailTemplate et = [
                SELECT Id, Subject, HtmlValue 
                FROM EmailTemplate 
                WHERE DeveloperName = :templateName 
                LIMIT 1
            ];
            
            ManagerNotificationData data = new ManagerNotificationData();
            data.design = design;
            data.action = action;
            data.comments = comments;

            Messaging.SingleEmailMessage mail = buildManagerEmail(et, toAddresses, data);

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        } catch (Exception e) {
            System.debug('Failed to send manager response notification: ' + e.getMessage());
        }
    }

    private static List<String> getManagerRecipients(Architecture_Design__c design) {
        List<String> toAddresses = new List<String>();

        if (design.Opportunity__r != null && String.isNotBlank(design.Opportunity__r.Supervisor_User_Email__c)) {
            toAddresses.add(design.Opportunity__r.Supervisor_User_Email__c);
        }

        String labelEmails = Label.Arelia_Living_Enrollment_Members;
        if (String.isNotBlank(labelEmails)) {
            List<String> extras = labelEmails.split('[,;]');
            for (String email : extras) {
                if (String.isNotBlank(email)) {
                    toAddresses.add(email.trim());
                }
            }
        }
        return toAddresses;
    }

    // --- Helpers to Reduce Complexity ---

    private static String resolveSupervisorName(Architecture_Design__c design) {
        String supervisorName = 'Enrollment Team';
        
        if (design.Opportunity__r != null && design.Opportunity__r.Supervisor_User__r != null) {
            String fname = design.Opportunity__r.Supervisor_User__r.FirstName;
            String lname = design.Opportunity__r.Supervisor_User__r.LastName;
            
            // Build full name safely
            String fullName = (fname != null ? fname + ' ' : '') + (lname != null ? lname : '');
            
            if (String.isNotBlank(fullName)) {
                supervisorName = fullName.trim();
            }
        }
        return supervisorName;
    }

    private static String resolveClientName(Architecture_Design__c design) {
        String clientName = 'Valued Client';
        
        if (design.Opportunity__r != null && design.Opportunity__r.Lead_Name__c != null) {
            clientName = design.Opportunity__r.Lead_Name__c;
        }
        return clientName;
    }

    private static Messaging.SingleEmailMessage buildManagerEmail(
        EmailTemplate et, 
        List<String> toAddresses, 
        ManagerNotificationData data
    ) {
        // Resolve dynamic data
        String projectName = (data.design.Opportunity__r != null) ? data.design.Opportunity__r.Name : 
                             (data.design.Project__r != null) ? data.design.Project__r.Name : 'Unknown Project';
        
        String safeComments = String.isNotBlank(data.comments) ? data.comments : 'No comments provided.';
        String decisionLabel = (data.action == 'Approve') ? 'Approved' : 'Rejected / Changes Requested';

        // Resolve names using helpers
        String supervisorName = resolveSupervisorName(data.design);
        String clientName = resolveClientName(data.design);

        // Replace Placeholders
        String htmlBody = et.HtmlValue;
        htmlBody = htmlBody.replace('[PROJECT_NAME]', projectName);
        htmlBody = htmlBody.replace('[DECISION]', decisionLabel);
        htmlBody = htmlBody.replace('[COMMENTS]', safeComments);
        htmlBody = htmlBody.replace('[SUPERVISOR_NAME]', supervisorName);
        htmlBody = htmlBody.replace('[CLIENT_NAME]', clientName);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(toAddresses);
        mail.setSubject(et.Subject);
        mail.setHtmlBody(htmlBody);

        try {
            String owdAddress = System.Label.Arelia_OWD;
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :owdAddress LIMIT 1];
            if (!owd.isEmpty()) {
                mail.setOrgWideEmailAddressId(owd[0].Id);
            }
        } catch (Exception ex) { 
            System.debug('OWD Error: ' + ex.getMessage()); 
        }

        return mail;
    }
}