public without sharing class vendorAssignmentController {
    
       private static final String EMAIL_TEMPLATE_DEVELOPER_NAME = Label.Arelia_Living_Vendor_Project_Assignment;

    @AuraEnabled(cacheable=true)
    public static List<Vendor_Assignment__c> getVendorTasks() {
        Id contactId = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId()].ContactId;
        return [SELECT Id, Name, Vendor_Work_End_Date__c, Vendor_Work_Start_Date__c,
                Completion__c, Project__c, Supervisor_User__c
                FROM Vendor_Assignment__c WHERE Vendor__c = :contactId];
    }

    public static void sendVendorAssignmentEmail(List<Vendor_Assignment__c> assignments) {
        if (assignments == null || assignments.isEmpty()) {return;}

        Set<Id> assignmentIds = new Map<Id, Vendor_Assignment__c>(assignments).keySet();
        List<Vendor_Assignment__c> vendorAssignments = fetchVendorAssignments(assignmentIds);
        EmailTemplate template = loadEmailTemplate();

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Vendor_Assignment__c va : vendorAssignments) {
            if (String.isBlank(va.Vendor__r?.Email__c)) {continue;}

            Messaging.SingleEmailMessage email = buildEmail(template, va);
            if (email != null) {emails.add(email);}
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
            return [SELECT Id, Subject, HtmlValue
                    FROM EmailTemplate
                    WHERE DeveloperName = :EMAIL_TEMPLATE_DEVELOPER_NAME
                    WITH SECURITY_ENFORCED LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load email template: ' + e.getMessage());
        }
    }

    private static Messaging.SingleEmailMessage buildEmail(EmailTemplate template, Vendor_Assignment__c va) {
        String htmlBody = template.HtmlValue
            .replace('{{{Vendor_Assignment__c.Project__c}}}', String.valueOf(va.Project__r?.Name))
            .replace('{{{Vendor_Assignment__c.Vendor__c}}}', String.valueOf(va.Vendor__r?.Name))
            .replace('{{{Vendor_Assignment__c.Vendor_Work_Start_Date__c}}}', 
                     va.Vendor_Work_Start_Date__c != null ? String.valueOf(va.Vendor_Work_Start_Date__c.format()) : '')
            .replace('{{{Vendor_Assignment__c.Vendor_Work_End_Date__c}}}', 
                     va.Vendor_Work_End_Date__c != null ? String.valueOf(va.Vendor_Work_End_Date__c.format()) : '')
            .replace('{{{Vendor_Assignment__c.Supervisor_User__c}}}', String.valueOf(va.Supervisor_User__r?.Name))
            .replace('{{{Vendor_Assignment__c.Supervisor_Email}}}', String.valueOf(va.Supervisor_User__r?.Email))
            .replace('{{{Vendor_Assignment__c.Supervisor_Phone}}}', String.valueOf(va.Supervisor_User__r?.Phone))
            .replace('{{{Vendor_Assignment__c.Vendor_Category__c}}}', String.valueOf(va.Vendor_Category__c));

        String subject = template.Subject
            .replace('{{{Vendor_Assignment__c.Project__c}}}', String.valueOf(va.Project__r?.Name));

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ va.Vendor__r.Email__c });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setWhatId(va.Id);
        email.setSaveAsActivity(false);

        Id orgWideEmailId = getOrgWideEmailAddressId();
        if (orgWideEmailId != null) email.setOrgWideEmailAddressId(orgWideEmailId);

        return email;
    }

    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owea = [
            SELECT Id FROM OrgWideEmailAddress 
            WHERE Address =: Label.Arelia_OWD 
            WITH SECURITY_ENFORCED LIMIT 1];
        return owea.isEmpty() ? null : owea[0].Id;
    }
}