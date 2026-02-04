public class ManagerApprovalHelper {

    @InvocableMethod(label='Send Manager Approval Email' description='Sends email with attachment to Manager Label')
    public static void sendEmailWithAttachment(List<Id> designIds) {
        System.debug('### START: ManagerApprovalHelper ###');
        
        if(designIds.isEmpty()) {
            System.debug('### ERROR: designIds list is empty. Exiting.');
            return;
        }
        
        Id recordId = designIds[0]; 
        System.debug('### Processing Record ID: ' + recordId);

        try {
            // --- 1. Get Recipients ---
            String emailLabel = System.Label.Arelia_Living_Enrollment_Members;
            System.debug('### Label Value (Raw): ' + emailLabel);
            
            List<String> toAddresses = new List<String>();

            if (String.isNotBlank(emailLabel)) {
                for (String email : emailLabel.split('[,;]')) {
                    if (String.isNotBlank(email)) {
                        toAddresses.add(email.trim());
                    }
                }
            }
            System.debug('### Parsed Email List: ' + toAddresses);
            
            if (toAddresses.isEmpty()) {
                System.debug('### ERROR: No valid emails found in Label. Exiting.');
                return;
            }

            // --- 2. Get Site URL ---
            String siteUrl = System.Label.Arelia_Site_Label; 
            if(siteUrl != null && siteUrl.endsWith('/')) {
                siteUrl = siteUrl.removeEnd('/');
            }
            System.debug('### Site URL: ' + siteUrl);

            // --- 3. Render Template ---
            List<EmailTemplate> etList = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = 'Architecture_Manager_Approval' LIMIT 1];
            if(etList.isEmpty()) {
                System.debug('### ERROR: Email Template "Architecture_Manager_Approval" NOT FOUND.');
                return;
            }
            EmailTemplate et = etList[0];
            System.debug('### Template Found: ' + et.Id);
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            // This method renders the merge fields based on the Record ID
            Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(et.Id, null, recordId);
            
            String subject = renderedMail.getSubject();
            String htmlBody = renderedMail.getHtmlBody();
            
            // Replace Placeholder
            if(htmlBody != null && siteUrl != null) {
                htmlBody = htmlBody.replace('[SITE_URL]', siteUrl);
            }
            
            mail.setSubject(subject);
            mail.setHtmlBody(htmlBody);
            mail.setToAddresses(toAddresses);
            System.debug('### Email Subject & Body prepared.');

            // --- 4. Attach File ---
            List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId LIMIT 1];
            System.debug('### Attachments Found (Count): ' + links.size());
            
            if(!links.isEmpty()) {
                ContentVersion cv = [SELECT VersionData, Title, FileExtension FROM ContentVersion 
                                     WHERE ContentDocumentId = :links[0].ContentDocumentId AND IsLatest = true LIMIT 1];
                
                System.debug('### Attaching File: ' + cv.Title + '.' + cv.FileExtension);

                Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
                attach.setFileName(cv.Title + '.' + cv.FileExtension);
                attach.setBody(cv.VersionData);
                mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
            } else {
                System.debug('### WARNING: No files attached to this record. Sending email without attachment.');
            }

            // --- 5. Send ---
            System.debug('### Attempting to send email...');
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            if (results[0].isSuccess()) {
                System.debug('### SUCCESS: Email sent successfully.');
            } else {
                System.debug('### FAILED to send email: ' + results[0].getErrors()[0].getMessage());
            }

        } catch (Exception e) {
            System.debug('### EXCEPTION: ' + e.getMessage());
            System.debug('### Stack Trace: ' + e.getStackTraceString());
        }
        
        System.debug('### END: ManagerApprovalHelper ###');
    }
}