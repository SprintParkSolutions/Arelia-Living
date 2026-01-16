public without sharing class ImageApprovalController {

    // --- 1. INTERNAL: Send Email & Re-Parent File ---
    @AuraEnabled
    public static void sendApprovalRequest(Id recordId, String fileId) {
        
        
        try {
            // A. Get File Info
            ContentVersion cv = [SELECT Id, Title, FileExtension, ContentDocumentId 
                                 FROM ContentVersion 
                                 WHERE ContentDocumentId = :fileId AND IsLatest = true LIMIT 1];

            // B. Create "Architecture Design" Record
            String token = UUID.randomUUID().toString();
            Architecture_Design__c designRec = new Architecture_Design__c();
            
            // Check for existing record
            List<Architecture_Design__c> existing = [SELECT Id FROM Architecture_Design__c WHERE Related_File_Id__c = :fileId LIMIT 1];
            
            if(!existing.isEmpty()) {
                designRec = existing[0];
            } else {
                designRec.Related_File_Id__c = fileId;
                
                // Dynamic Parent Linking
                String sObjName = recordId.getSObjectType().getDescribe().getName();
                if(sObjName == 'Opportunity') {
                    designRec.Opportunity__c = recordId;
                } else if(sObjName == 'Project__c') {
                    designRec.Project__c = recordId; 
                }
            }
            
            designRec.Secure_Token__c = token;
            designRec.Status__c = 'Sent';
            
            upsert designRec; 

            // =================================================================
            // RE-PARENTING LOGIC (The Fix)
            // =================================================================
            
            // 1. Create Link to Architecture_Design__c (Child)
            List<ContentDocumentLink> childLinkCheck = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :designRec.Id AND ContentDocumentId = :fileId LIMIT 1];
            
            if(childLinkCheck.isEmpty()) {
                ContentDocumentLink newLink = new ContentDocumentLink();
                newLink.LinkedEntityId = designRec.Id;
                newLink.ContentDocumentId = fileId;
                newLink.ShareType = 'V'; // Viewer
                newLink.Visibility = 'AllUsers'; // CRITICAL: Makes it show in the related list!
                insert newLink;
            }

            // 2. Delete Link from Opportunity (Parent)
            List<ContentDocumentLink> parentLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :recordId AND ContentDocumentId = :fileId];
            if(!parentLinks.isEmpty()) {
                delete parentLinks;
            }
            // =================================================================

            // C. Send Email
            sendEmailToClient(recordId, cv, token);

        } catch (Exception e) {
            
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    private static void sendEmailToClient(Id recordId, ContentVersion cvFile, String token) {
        // (Keep previous email logic exactly as is)
        String recipientEmail;
        String sObjName = recordId.getSObjectType().getDescribe().getName();

        if(sObjName == 'Opportunity') {
            Opportunity opp = [SELECT Email__c FROM Opportunity WHERE Id = :recordId]; 
            recipientEmail = opp.Email__c;
        } else if(sObjName == 'Project__c') {
             String query = 'SELECT Client_Email__c FROM Project__c WHERE Id = :recordId LIMIT 1';
             SObject proj = Database.query(query);
             recipientEmail = (String)proj.get('Client_Email__c');
        }

        if(String.isBlank(recipientEmail)) throw new AuraHandledException('No email address found.');

        String baseUrl = System.Label.Arelia_Site_Label; 
        String pageUrl = System.Label.Image_Approval;   
        String fullLink = baseUrl +  pageUrl + '?token=' + token;

        EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = 'Client_Image_Approval_Request' LIMIT 1];
        String htmlBody = et.HtmlValue;
        String subject = et.Subject;

        if(htmlBody != null) {
            htmlBody = htmlBody.replace('[APPROVAL_LINK]', fullLink);
            htmlBody = htmlBody.replace('[FILE_TITLE]', cvFile.Title);
        }
        if(subject != null) subject = subject.replace('[FILE_TITLE]', cvFile.Title);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        try {
            String owdAddress = System.Label.Arelia_OWD;
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :owdAddress LIMIT 1];
            if (!owd.isEmpty()) mail.setOrgWideEmailAddressId(owd[0].Id);
        } catch (Exception ex) { System.debug('OWD Error'); }

        mail.setToAddresses(new String[] { recipientEmail });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        
        ContentVersion fullCv = [SELECT VersionData, Title, FileExtension FROM ContentVersion WHERE Id = :cvFile.Id LIMIT 1];
        Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
        attach.setFileName(fullCv.Title + '.' + fullCv.FileExtension);
        attach.setBody(fullCv.VersionData);
        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
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
        
        if(designs.isEmpty()) return designList;

        Set<String> fileIds = new Set<String>();
        for(Architecture_Design__c ad : designs) fileIds.add(ad.Related_File_Id__c);

        Map<String, ContentVersion> fileMap = new Map<String, ContentVersion>();
        for(ContentVersion cv : [SELECT ContentDocumentId, Title, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :fileIds AND IsLatest = true]) {
            fileMap.put(cv.ContentDocumentId, cv);
        }

        for(Architecture_Design__c ad : designs) {
            if(fileMap.containsKey(ad.Related_File_Id__c)) {
                ContentVersion cv = fileMap.get(ad.Related_File_Id__c);
                DesignWrapper wrapper = new DesignWrapper();
                wrapper.id = ad.Id; 
                wrapper.title = cv.Title;
                wrapper.extension = cv.FileExtension;
                wrapper.status = ad.Status__c;
                
                wrapper.statusClass = 'slds-badge';
                if(wrapper.status == 'Approved') wrapper.statusClass += ' slds-theme_success';
                else if(wrapper.status == 'Changes Requested') wrapper.statusClass += ' slds-theme_error';
                else wrapper.statusClass += ' slds-theme_warning';
                
                designList.add(wrapper);
            }
        }
        return designList;
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
    public static Map<String, String> getFileByToken(String token, String versionId) {
        try {
            Architecture_Design__c design = [SELECT Status__c, Comments__c, Related_File_Id__c 
                                             FROM Architecture_Design__c WHERE Secure_Token__c = :token LIMIT 1];
            
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

    // --- 4. EXTERNAL: Submit Decision ---
    @AuraEnabled
    public static void submitDecision(String token, String versionId, String status, String comments) {
        try {
            Architecture_Design__c design = [SELECT Id FROM Architecture_Design__c WHERE Secure_Token__c = :token LIMIT 1];
            design.Status__c = status;
            design.Comments__c = comments;
            update design;
        } catch(Exception e) { throw new AuraHandledException(e.getMessage()); }
    }
}