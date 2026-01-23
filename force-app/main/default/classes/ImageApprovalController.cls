/**
 * @description Controller for Client Image Approval LWC.
 * Handles file uploads, email notifications, and secure token-based approvals.
 * * SECURITY NOTE: This class is 'without sharing' to allow Site Guest Users (Clients)
 * to view and update specific records using a Secure Token. 
 * Standard CRUD checks are suppressed as this is a system-level process.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ImageApprovalController {

    /**
     * @description Wrapper to fix ExcessiveParameterList violation.
     */
    private class NotificationData {
        public Architecture_Design__c design;
        public String status;
        public String comments;
    }

    /**
     * @description Helper struct to simplify recipient logic
     */
    private class RecipientInfo {
        public String email;
        public String name;
    }

    // --- 1. INTERNAL: Send Email & Re-Parent File ---
    @AuraEnabled
    public static void sendApprovalRequest(Id recordId, String fileId) {
        try {
            // 1. Get File Info
            ContentVersion cv = getLatestContentVersion(fileId);

            // 2. Create/Update Architecture Design Record
            Architecture_Design__c designRec = createDesignRecord(recordId, fileId);

            // 3. Manage File Permissions (Re-parenting)
            shareFileWithDesign(designRec.Id, fileId, recordId);

            // 4. Send Email
            sendEmailToClient(recordId, cv, designRec.Secure_Token__c);

            // 5. Update Opportunity Status
            updateOpportunityStatus(recordId);

        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    // --- Helpers for sendApprovalRequest ---

    private static ContentVersion getLatestContentVersion(String fileId) {
        return [
            SELECT Id, Title, FileExtension, ContentDocumentId 
            FROM ContentVersion 
            WHERE ContentDocumentId = :fileId AND IsLatest = true 
            LIMIT 1
        ];
    }

    private static Architecture_Design__c createDesignRecord(Id recordId, String fileId) {
        String token = UUID.randomUUID().toString();
        Architecture_Design__c designRec = new Architecture_Design__c();
        
        List<Architecture_Design__c> existing = [
            SELECT Id FROM Architecture_Design__c 
            WHERE Related_File_Id__c = :fileId 
            LIMIT 1
        ];
        
        if (!existing.isEmpty()) {
            designRec = existing[0];
        } else {
            designRec.Related_File_Id__c = fileId;
            String sObjName = recordId.getSObjectType().getDescribe().getName();
            if (sObjName == 'Opportunity') {
                designRec.Opportunity__c = recordId;
            } else if (sObjName == 'Project__c') {
                designRec.Project__c = recordId; 
            }
        }
        
        designRec.Secure_Token__c = token;
        designRec.Status__c = 'Sent';
        upsert designRec;
        return designRec;
    }

    private static void shareFileWithDesign(Id designId, String fileId, Id parentRecordId) {
        // Link to Design Record
        List<ContentDocumentLink> childLinkCheck = [
            SELECT Id FROM ContentDocumentLink 
            WHERE LinkedEntityId = :designId AND ContentDocumentId = :fileId 
            LIMIT 1
        ];
        
        if (childLinkCheck.isEmpty()) {
            insert new ContentDocumentLink(
                LinkedEntityId = designId, 
                ContentDocumentId = fileId, 
                ShareType = 'V', 
                Visibility = 'AllUsers'
            );
        }

        // Remove Link from Parent (Cleanup)
        List<ContentDocumentLink> parentLinks = [
            SELECT Id FROM ContentDocumentLink 
            WHERE LinkedEntityId = :parentRecordId AND ContentDocumentId = :fileId
        ];
        if (!parentLinks.isEmpty()) {
            delete parentLinks;
        }
    }

    private static void updateOpportunityStatus(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            update new Opportunity(
                Id = recordId, 
                Architecture_Client_Approval_Sent__c = true
            );
        }
    }

    // --- Email Logic ---

    private static void sendEmailToClient(Id recordId, ContentVersion cvFile, String token) {
        // Extracted recipient logic to reduce complexity
        RecipientInfo recipient = fetchRecipientDetails(recordId);

        String baseUrl = System.Label.Arelia_Site_Label; 
        String pageUrl = System.Label.Image_Approval;   
        String fullLink = baseUrl +  pageUrl + '?token=' + token;
        String templateName = Label.Client_Image_Approval_Template;
        
        EmailTemplate et = [
            SELECT Id, Subject, HtmlValue 
            FROM EmailTemplate 
            WHERE DeveloperName = :templateName 
            LIMIT 1
        ];
        
        String htmlBody = et.HtmlValue;
        if (htmlBody != null) {
            htmlBody = htmlBody.replace('[APPROVAL_LINK]', fullLink);
            htmlBody = htmlBody.replace('[FILE_TITLE]', cvFile.Title);
            htmlBody = htmlBody.replace('[CLIENT_NAME]', recipient.name);
        }
        
        String subject = et.Subject;
        if (subject != null) {
            subject = subject.replace('[FILE_TITLE]', cvFile.Title);
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        try {
            String owdAddress = System.Label.Arelia_OWD;
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :owdAddress LIMIT 1];
            if (!owd.isEmpty()) {
                mail.setOrgWideEmailAddressId(owd[0].Id);
            }
        } catch (Exception ex) { 
            System.debug('OWD Error'); 
        }

        mail.setToAddresses(new String[] { recipient.email });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        
        ContentVersion fullCv = [
            SELECT VersionData, Title, FileExtension 
            FROM ContentVersion 
            WHERE Id = :cvFile.Id 
            LIMIT 1
        ];
        Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
        attach.setFileName(fullCv.Title + '.' + fullCv.FileExtension);
        attach.setBody(fullCv.VersionData);
        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // New Helper to reduce Complexity in sendEmailToClient
    private static RecipientInfo fetchRecipientDetails(Id recordId) {
        RecipientInfo info = new RecipientInfo();
        info.name = 'Valued Client'; // Default name

        String sObjName = recordId.getSObjectType().getDescribe().getName();

        if (sObjName == 'Opportunity') {
            Opportunity opp = [SELECT Email__c, Lead_Name__c FROM Opportunity WHERE Id = :recordId]; 
            info.email = opp.Email__c;
            if (opp.Lead_Name__c != null) {
                info.name = opp.Lead_Name__c;
            }
        } else if (sObjName == 'Project__c') {
             String query = 'SELECT Client_Email__c FROM Project__c WHERE Id = :recordId LIMIT 1';
             SObject proj = Database.query(query);
             info.email = (String)proj.get('Client_Email__c');
        }

        if (String.isBlank(info.email)) {
            throw new AuraHandledException('No email address found.');
        }
        return info;
    }

    // --- 2. INTERNAL: Get History ---
    @AuraEnabled(cacheable=true)
    public static List<DesignWrapper> getRelatedImages(Id recordId) {
        List<DesignWrapper> designList = new List<DesignWrapper>();
        
        List<Architecture_Design__c> designs = [
            SELECT Id, Related_File_Id__c, Status__c, CreatedDate
            FROM Architecture_Design__c 
            WHERE Opportunity__c = :recordId 
               OR Project__c = :recordId
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
                ContentVersion cv = fileMap.get(ad.Related_File_Id__c);
                designList.add(buildDesignWrapper(ad, cv));
            }
        }
        return designList;
    }

    // Helper to reduce Complexity in getRelatedImages
    private static DesignWrapper buildDesignWrapper(Architecture_Design__c ad, ContentVersion cv) {
        DesignWrapper wrapper = new DesignWrapper();
        wrapper.id = ad.Id; 
        wrapper.title = cv.Title; 
        wrapper.extension = cv.FileExtension; 
        wrapper.status = ad.Status__c;
        
        String badgeTheme = 'slds-theme_warning'; // Default
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

    // --- 3. EXTERNAL: Get Details ---
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFileByToken(String token) {
        try {
            Architecture_Design__c design = [
                SELECT Status__c, Comments__c, Related_File_Id__c 
                FROM Architecture_Design__c 
                WHERE Secure_Token__c = :token 
                LIMIT 1
            ];
            
            ContentDocument doc = [
                SELECT Title 
                FROM ContentDocument 
                WHERE Id = :design.Related_File_Id__c 
                LIMIT 1
            ];

            Map<String, String> result = new Map<String, String>();
            result.put('title', doc.Title);
            result.put('status', design.Status__c);
            result.put('comments', design.Comments__c);
            return result;
        } catch (Exception e) { 
            throw new AuraHandledException('Invalid Link or Record Not Found'); 
        }
    }

    // --- 4. EXTERNAL: Submit Decision ---
    @AuraEnabled
    public static void submitDecision(String token, String status, String comments) {
        try {
            Architecture_Design__c design = [
                SELECT Id, Status__c, Comments__c, 
                       Opportunity__r.Name, 
                       Opportunity__r.Lead_Name__c, 
                       Opportunity__r.Supervisor_User_Email__c, 
                       Opportunity__r.Supervisor_User__r.Name,
                       Project__r.Name
                FROM Architecture_Design__c 
                WHERE Secure_Token__c = :token 
                LIMIT 1
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

            String templateName = Label.Client_Response_Notification_Template;
            EmailTemplate et = [
                SELECT Id, Subject, HtmlValue 
                FROM EmailTemplate 
                WHERE DeveloperName = :templateName 
                LIMIT 1
            ];
            
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
            for(String email : extras) {
                if (String.isNotBlank(email)) {
                    toAddresses.add(email.trim());
                }
            }
        }
        return toAddresses;
    }

    private static Messaging.SingleEmailMessage buildNotificationEmail(
        EmailTemplate et, 
        List<String> toAddresses, 
        NotificationData data
    ) {
        String projectName = (data.design.Opportunity__r != null) ? data.design.Opportunity__r.Name : 
                             (data.design.Project__r != null) ? data.design.Project__r.Name : 'Unknown Project';
        
        String safeComments = String.isNotBlank(data.comments) ? data.comments : 'No comments provided.';
        
        String supervisorName = (data.design.Opportunity__r != null && data.design.Opportunity__r.Supervisor_User__r.Name != null) ? data.design.Opportunity__r.Supervisor_User__r.Name : 'Enrollment Team';
        String clientName = (data.design.Opportunity__r != null && data.design.Opportunity__r.Lead_Name__c != null) ? data.design.Opportunity__r.Lead_Name__c : 'Valued Client';

        String htmlBody = et.HtmlValue;
        htmlBody = htmlBody.replace('[PROJECT_NAME]', projectName);
        htmlBody = htmlBody.replace('[DECISION]', data.status);
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