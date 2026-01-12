public without sharing class vendorAssignmentController {
    
    private static final String EMAIL_TEMPLATE_DEVELOPER_NAME = Label.Arelia_Living_Vendor_Project_Assignment;

    @AuraEnabled(cacheable=true)
    public static List<Vendor_Assignment__c> getVendorTasks() {
        // Fix: Added WITH SECURITY_ENFORCED for CRUD check
        List<User> currentUser = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() WITH SECURITY_ENFORCED LIMIT 1];
        Id contactId = (currentUser.isEmpty()) ? null : currentUser[0].ContactId;

        // Fix: Added WITH SECURITY_ENFORCED for CRUD check
        return [SELECT Id, Name, Vendor_Work_End_Date__c, Vendor_Work_Start_Date__c,
                Completion__c, Project__c, Supervisor_User__c
                FROM Vendor_Assignment__c WHERE Vendor__c = :contactId
                WITH SECURITY_ENFORCED];
    }

    public static void sendVendorAssignmentEmail(List<Vendor_Assignment__c> assignments) {
        // Fix: Added braces for PMD
        if (assignments == null || assignments.isEmpty()) { 
            return; 
        }

        Set<Id> assignmentIds = new Map<Id, Vendor_Assignment__c>(assignments).keySet();
        List<Vendor_Assignment__c> vendorAssignments = fetchVendorAssignments(assignmentIds);
        EmailTemplate template = loadEmailTemplate();
        
        // Fix: Added braces for PMD
        if (template == null) { 
            return; 
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Vendor_Assignment__c va : vendorAssignments) {
            // Fix: Added braces for PMD
            if (va.Vendor__r == null || String.isBlank(va.Vendor__r.Email__c)) { 
                continue; 
            }

            Messaging.SingleEmailMessage email = buildEmail(template, va);
            // Fix: Added braces for PMD
            if (email != null) { 
                emails.add(email); 
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                throw new AuraHandledException('Email send failed: ' + e.getMessage());
            }
        }
    }

    private static List<Vendor_Assignment__c> fetchVendorAssignments(Set<Id> assignmentIds) {
        return [
            SELECT Id, Vendor_Work_Start_Date__c, Vendor_Work_End_Date__c, Vendor_Category__c,
                   Vendor__r.Email__c, Vendor__r.Name,
                   Project__r.Name,
                   Supervisor_User__r.Name, Supervisor_User__r.Email, Supervisor_User__r.Phone
            FROM Vendor_Assignment__c
            WHERE Id IN :assignmentIds
            WITH SECURITY_ENFORCED
        ];
    }

    private static EmailTemplate loadEmailTemplate() {
        try {
            return [SELECT Id, Subject, HtmlValue, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = :EMAIL_TEMPLATE_DEVELOPER_NAME
                    WITH SECURITY_ENFORCED LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load email template: ' + EMAIL_TEMPLATE_DEVELOPER_NAME);
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(EmailTemplate template, Vendor_Assignment__c va) {
        String rawBody = String.isNotBlank(template.HtmlValue) ? template.HtmlValue : template.Body;
        
        // Fix: Added braces for PMD
        if (rawBody == null) { 
            rawBody = ''; 
        }

        // Helper strings to avoid NPE in replace
        String projName = va.Project__r?.Name != null ? va.Project__r.Name : '';
        String vendName = va.Vendor__r?.Name != null ? va.Vendor__r.Name : '';
        String startDate = va.Vendor_Work_Start_Date__c != null ? va.Vendor_Work_Start_Date__c.format() : '';
        String endDate = va.Vendor_Work_End_Date__c != null ? va.Vendor_Work_End_Date__c.format() : '';
        String supName = va.Supervisor_User__r?.Name != null ? va.Supervisor_User__r.Name : '';
        String supEmail = va.Supervisor_User__r?.Email != null ? va.Supervisor_User__r.Email : '';
        String supPhone = va.Supervisor_User__r?.Phone != null ? va.Supervisor_User__r.Phone : '';
        String category = va.Vendor_Category__c != null ? va.Vendor_Category__c : '';

        String htmlBody = rawBody
            .replace('{{{Vendor_Assignment__c.Project__c}}}', projName)
            .replace('{{{Vendor_Assignment__c.Vendor__c}}}', vendName)
            .replace('{{{Vendor_Assignment__c.Vendor_Work_Start_Date__c}}}', startDate)
            .replace('{{{Vendor_Assignment__c.Vendor_Work_End_Date__c}}}', endDate)
            .replace('{{{Vendor_Assignment__c.Supervisor_User__c}}}', supName)
            .replace('{{{Vendor_Assignment__c.Supervisor_Email}}}', supEmail)
            .replace('{{{Vendor_Assignment__c.Supervisor_Phone}}}', supPhone)
            .replace('{{{Vendor_Assignment__c.Vendor_Category__c}}}', category);

        String rawSubject = template.Subject != null ? template.Subject : '';
        String subject = rawSubject
            .replace('{{{Vendor_Assignment__c.Project__c}}}', projName);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ va.Vendor__r.Email__c });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setWhatId(va.Id);
        email.setSaveAsActivity(false);

        Id orgWideEmailId = getOrgWideEmailAddressId();
        // Fix: Added braces for PMD
        if (orgWideEmailId != null) { 
            email.setOrgWideEmailAddressId(orgWideEmailId); 
        }

        return email;
    }

    private static Id getOrgWideEmailAddressId() {
        // Fix: Added braces for PMD
        if (String.isBlank(Label.Arelia_OWD)) { 
            return null; 
        }
        
        List<OrgWideEmailAddress> owea = [
            SELECT Id FROM OrgWideEmailAddress 
            WHERE Address =: Label.Arelia_OWD 
            WITH SECURITY_ENFORCED LIMIT 1];
        return owea.isEmpty() ? null : owea[0].Id;
    }
}