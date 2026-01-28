/**
 * @description Controller for Client Image Approval LWC.
 * Handles file uploads, email notifications, and secure token-based approvals.
 * * SECURITY NOTE: This class is explicitly 'without sharing' to allow external Managers 
 * (operating as Guest Users) to view specific records via ID and perform updates.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ImageApprovalController {

    // --- Inner Classes for Data Transfer ---
    private class NotificationData {
        public Architecture_Design__c design;
        public String status;
        public String comments;
    }

    private class RecipientInfo {
        public String email;
        public String name;
    }

    private class ResolvedNames {
        public String supervisorName;
        public String clientName;
    }

    // --- 1. INTERNAL: Send Email & Re-Parent File ---
    @AuraEnabled
    public static void sendApprovalRequest(Id recordId, String fileId) {
        try {
            ContentVersion cv = getLatestContentVersion(fileId);
            Architecture_Design__c designRec = getOrInitDesignRecord(recordId, fileId);
            
            shareFileWithDesign(designRec.Id, fileId, recordId);
            sendEmailToClient(recordId, cv, designRec.Secure_Token__c);
            updateOpportunityStatus(recordId);

        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    // --- Helpers: Design Record Management ---

    private static ContentVersion getLatestContentVersion(String fileId) {
        return [SELECT Id, Title, FileExtension, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId = :fileId AND IsLatest = true LIMIT 1];
    }

    private static Architecture_Design__c getOrInitDesignRecord(Id recordId, String fileId) {
        List<Architecture_Design__c> existing = [SELECT Id FROM Architecture_Design__c WHERE Related_File_Id__c = :fileId LIMIT 1];
        
        Architecture_Design__c designRec;
        if (!existing.isEmpty()) {
            designRec = existing[0];
        } else {
            designRec = new Architecture_Design__c();
            designRec.Related_File_Id__c = fileId;
            linkDesignToParent(designRec, recordId);
        }
        
        designRec.Secure_Token__c = UUID.randomUUID().toString();
        designRec.Status__c = 'Sent';
        upsert designRec;
        return designRec;
    }

    private static void linkDesignToParent(Architecture_Design__c designRec, Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            designRec.Opportunity__c = recordId;
        } else if (sObjName == 'Project__c') {
            designRec.Project__c = recordId; 
        }
    }

    private static void shareFileWithDesign(Id designId, String fileId, Id parentRecordId) {
        List<ContentDocumentLink> childLinkCheck = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :designId AND ContentDocumentId = :fileId LIMIT 1];
        if (childLinkCheck.isEmpty()) {
            insert new ContentDocumentLink(LinkedEntityId = designId, ContentDocumentId = fileId, ShareType = 'V', Visibility = 'AllUsers');
        }

        List<ContentDocumentLink> parentLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :parentRecordId AND ContentDocumentId = :fileId];
        if (!parentLinks.isEmpty()) {
            delete parentLinks;
        }
    }

    private static void updateOpportunityStatus(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            update new Opportunity(Id = recordId, Architecture_Client_Approval_Sent__c = true);
        }
    }

    // --- 2. INTERNAL: Email Logic ---

    private static void sendEmailToClient(Id recordId, ContentVersion cvFile, String token) {
        RecipientInfo recipient = fetchRecipientDetails(recordId);

        String fullLink = System.Label.Arelia_Site_Label + System.Label.Image_Approval + '?token=' + token;
        
        EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :Label.Client_Image_Approval_Template LIMIT 1];
        
        String htmlBody = et.HtmlValue;
        if (htmlBody != null) {
            htmlBody = htmlBody.replace('[APPROVAL_LINK]', fullLink)
                               .replace('[FILE_TITLE]', cvFile.Title)
                               .replace('[CLIENT_NAME]', recipient.name);
        }
        
        String subject = et.Subject;
        if (subject != null) {
            subject = subject.replace('[FILE_TITLE]', cvFile.Title);
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        setOrgWideAddress(mail);
        mail.setToAddresses(new String[] { recipient.email });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        
        ContentVersion fullCv = [SELECT VersionData, Title, FileExtension FROM ContentVersion WHERE Id = :cvFile.Id LIMIT 1];
        Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
        attach.setFileName(fullCv.Title + '.' + fullCv.FileExtension);
        attach.setBody(fullCv.VersionData);
        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // --- Helpers: Recipient Resolution (Split to reduce complexity) ---

    private static RecipientInfo fetchRecipientDetails(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            return fetchOpportunityRecipient(recordId);
        } 
        if (sObjName == 'Project__c') {
            return fetchProjectRecipient(recordId);
        }
        throw new AuraHandledException('Unsupported Object Type');
    }

    private static RecipientInfo fetchOpportunityRecipient(Id recordId) {
        Opportunity opp = [SELECT Email__c, Lead_Name__c FROM Opportunity WHERE Id = :recordId]; 
        if (String.isBlank(opp.Email__c)) {
            throw new AuraHandledException('No email address found on Opportunity.');
        }
        RecipientInfo info = new RecipientInfo();
        info.email = opp.Email__c;
        info.name = (opp.Lead_Name__c != null) ? opp.Lead_Name__c : 'Valued Client';
        return info;
    }

    private static RecipientInfo fetchProjectRecipient(Id recordId) {
        String query = 'SELECT Client_Email__c FROM Project__c WHERE Id = :recordId LIMIT 1';
        SObject proj = Database.query(query);
        String email = (String)proj.get('Client_Email__c');
        
        if (String.isBlank(email)) {
            throw new AuraHandledException('No email address found on Project.');
        }
        RecipientInfo info = new RecipientInfo();
        info.email = email;
        info.name = 'Valued Client';
        return info;
    }

    private static void setOrgWideAddress(Messaging.SingleEmailMessage mail) {
        try {
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :System.Label.Arelia_OWD LIMIT 1];
            if (!owd.isEmpty()) {
                mail.setOrgWideEmailAddressId(owd[0].Id);
            }
        } catch (Exception ex) { 
            System.debug('OWD Error'); 
        }
    }

    // --- 3. INTERNAL: Get History ---
    @AuraEnabled(cacheable=true)
    public static List<DesignWrapper> getRelatedImages(Id recordId) {
        List<DesignWrapper> designList = new List<DesignWrapper>();
        List<Architecture_Design__c> designs = [
            SELECT Id, Related_File_Id__c, Status__c, CreatedDate 
            FROM Architecture_Design__c 
            WHERE Opportunity__c = :recordId OR Project__c = :recordId 
            ORDER BY CreatedDate DESC
        ];
        
        if (designs.isEmpty()) {
            return designList;
        }

        Set<String> fileIds = new Set<String>();
        for (Architecture_Design__c ad : designs) {
            fileIds.add(ad.Related_File_Id__c);
        }

        Map<String, ContentVersion> fileMap = new Map<String, ContentVersion>();
        for (ContentVersion cv : [SELECT ContentDocumentId, Title, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :fileIds AND IsLatest = true]) {
            fileMap.put(cv.ContentDocumentId, cv);
        }

        for (Architecture_Design__c ad : designs) {
            if (fileMap.containsKey(ad.Related_File_Id__c)) {
                designList.add(buildDesignWrapper(ad, fileMap.get(ad.Related_File_Id__c)));
            }
        }
        return designList;
    }

    private static DesignWrapper buildDesignWrapper(Architecture_Design__c ad, ContentVersion cv) {
        DesignWrapper wrapper = new DesignWrapper();
        wrapper.id = ad.Id; 
        wrapper.title = cv.Title; 
        wrapper.extension = cv.FileExtension; 
        wrapper.status = ad.Status__c;
        
        String badgeTheme = 'slds-theme_warning'; 
        if (wrapper.status == 'Approved') {
            badgeTheme = 'slds-theme_success';
        } else if (wrapper.status == 'Changes Requested') {
            badgeTheme = 'slds-theme_error';
        }
        wrapper.statusClass = 'slds-badge ' + badgeTheme;
        return wrapper;
    }

    public class DesignWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public String status;
        @AuraEnabled public String statusClass;
    }

    // --- 4. EXTERNAL: Get Details ---
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFileByToken(String token) {
        try {
            Architecture_Design__c design = [SELECT Status__c, Comments__c, Related_File_Id__c FROM Architecture_Design__c WHERE Secure_Token__c = :token LIMIT 1];
            ContentDocument doc = [SELECT Title FROM ContentDocument WHERE Id = :design.Related_File_Id__c LIMIT 1];
            Map<String, String> result = new Map<String, String>();
            result.put('title', doc.Title);
            result.put('status', design.Status__c);
            result.put('comments', design.Comments__c);
            return result;
        } catch (Exception e) { 
            throw new AuraHandledException('Invalid Link or Record Not Found'); 
        }
    }

    // --- 5. EXTERNAL: Submit Decision ---
    @AuraEnabled
    public static void submitDecision(String token, String status, String comments) {
        try {
            Architecture_Design__c design = [
                SELECT Id, Status__c, Comments__c, 
                       Opportunity__r.Name, 
                       Opportunity__r.Lead_Name__c, 
                       Opportunity__r.Supervisor_User_Email__c, 
                       Opportunity__r.Supervisor_User__r.FirstName,
                       Opportunity__r.Supervisor_User__r.LastName,
                       Project__r.Name
                FROM Architecture_Design__c 
                WHERE Secure_Token__c = :token LIMIT 1
            ];

            design.Status__c = status;
            design.Comments__c = comments;
            update design;

            sendResponseNotification(design, status, comments);

        } catch (Exception e) { 
            throw new AuraHandledException(e.getMessage()); 
        }
    }

    // --- REFACTORED NOTIFICATION LOGIC ---

    private static void sendResponseNotification(Architecture_Design__c design, String status, String comments) {
        try {
            List<String> toAddresses = getNotificationRecipients(design);
            if (toAddresses.isEmpty()) {
                return;
            }

            EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :Label.Client_Response_Notification_Template LIMIT 1];
            
            NotificationData data = new NotificationData();
            data.design = design;
            data.status = status;
            data.comments = comments;

            Messaging.SingleEmailMessage mail = buildNotificationEmail(et, toAddresses, data);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        } catch (Exception e) {
            System.debug('Failed to send client response notification: ' + e.getMessage());
        }
    }

    private static List<String> getNotificationRecipients(Architecture_Design__c design) {
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

    private static Messaging.SingleEmailMessage buildNotificationEmail(EmailTemplate et, List<String> toAddresses, NotificationData data) {
        String projectName = (data.design.Opportunity__r != null) ? data.design.Opportunity__r.Name : 
                             (data.design.Project__r != null) ? data.design.Project__r.Name : 'Unknown Project';
        
        String safeComments = String.isNotBlank(data.comments) ? data.comments : 'No comments provided.';
        ResolvedNames rNames = resolveNames(data);

        String htmlBody = et.HtmlValue;
        htmlBody = htmlBody.replace('[PROJECT_NAME]', projectName)
                           .replace('[DECISION]', data.status)
                           .replace('[COMMENTS]', safeComments)
                           .replace('[SUPERVISOR_NAME]', rNames.supervisorName)
                           .replace('[CLIENT_NAME]', rNames.clientName);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        setOrgWideAddress(mail);
        mail.setToAddresses(toAddresses);
        mail.setSubject(et.Subject);
        mail.setHtmlBody(htmlBody);

        return mail;
    }

    // New Helper to resolve names and reduce complexity
    private static ResolvedNames resolveNames(NotificationData data) {
        ResolvedNames names = new ResolvedNames();
        names.supervisorName = 'Enrollment Team';
        names.clientName = 'Valued Client';

        if (data.design.Opportunity__r != null) {
            names.supervisorName = resolveSupervisorName(data.design.Opportunity__r);
            names.clientName = resolveClientName(data.design.Opportunity__r);
        }
        return names;
    }

    private static String resolveSupervisorName(Opportunity opp) {
        if (opp.Supervisor_User__r == null) {
            return 'Enrollment Team';
        }
        String fname = opp.Supervisor_User__r.FirstName;
        String lname = opp.Supervisor_User__r.LastName;
        String fullName = (fname != null ? fname + ' ' : '') + (lname != null ? lname : '');
        return String.isNotBlank(fullName) ? fullName.trim() : 'Enrollment Team';
    }

    private static String resolveClientName(Opportunity opp) {
        return (opp.Lead_Name__c != null) ? opp.Lead_Name__c : 'Valued Client';
    }
}