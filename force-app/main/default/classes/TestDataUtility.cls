@isTest
public class TestDataUtility {

    // 1. Create User
    public static User createSupervisorUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, 
            Email = alias + '@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = alias + DateTime.now().getTime() + '@testorg.com'
        );
        insert u;
        return u;
    }

    // 2. Create Project
    public static Project__c createProject(String name) {
        Project__c proj = new Project__c(
            Name = name, 
            Status__c = 'In Progress'
        );
        insert proj;
        return proj;
    }

    // 3. Create Opportunity
    public static Opportunity createOpportunity(String name, Id supervisorId) {
        Opportunity opp = new Opportunity(
            Name = name,
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            Supervisor_User__c = supervisorId,
            Project_Scope__c = 'Dining Hall'
        );
        insert opp;
        return opp;
    }

    // 4. Create Vendor
    public static Vendor__c createVendor(String name, String category, String email) {
        Vendor__c vendor = new Vendor__c(
            Name = name,
            Email__c = email,
            Vendor_Category__c = category,
            Vendor_Status__c = 'Available',
            Average_Efficiency__c = 95.5
        );
        insert vendor;
        return vendor;
    }

    // 5. Create File (ContentVersion)
    public static ContentVersion createContentVersion(String title, String fileContent) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf(fileContent),
            IsMajorVersion = true
        );
        insert cv;
        return cv;
    }

    // 6. Link File to Record (ContentDocumentLink)
    public static ContentDocumentLink linkFileToRecord(Id contentVersionId, Id linkedEntityId) {
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId].ContentDocumentId;
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = linkedEntityId,
            ContentDocumentId = conDocId,
            ShareType = 'V'
        );
        insert cdl;
        return cdl;
    }

    // 7. Create Email Templates
    public static void createEmailTemplates() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = new List<EmailTemplate>();
            
            templates.add(new EmailTemplate(
                DeveloperName = 'Backup_Tendor_Invitation',
                Name = 'Backup Tender Invitation',
                Subject = 'Tender: {{{project_scope}}}',
                HtmlValue = '<html><body>Test Email Backup {{{Vendor_Category__c}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            ));

            templates.add(new EmailTemplate(
                DeveloperName = 'Quatation_Email_Template',
                Name = 'Quotation Email Template',
                Subject = 'New Tender: {{{project_scope}}}',
                HtmlValue = '<html><body>Test Email New {{{Vendor_Category__c}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            ));
            
            insert templates;
        }
    }

    // ==========================================================================
    // Wrapper class to solve "Excessive Parameter List"
    // ==========================================================================
    public class AbscondDataParams {
        public Id oppId;
        public Id vendorId;
        public Id supervisorId;
        public Id projId;
        public String voStatus;
        public Decimal completion;
        
        // Removed the constructor. We will use property assignment directly.
    }

    // 8. Complex Data: Abscond Data
    public static void createAbscondData(AbscondDataParams params) {
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = params.oppId,
            Vendor__c = params.vendorId,
            Vendor_Opportunity_Status__c = params.voStatus
        );
        insert vo;

        Vendor_Assignment__c va = new Vendor_Assignment__c(
            Vendor_Opportunity__c = vo.Id,
            Opportunity__c = params.oppId,
            Supervisor_User__c = params.supervisorId,
            Project__c = params.projId,
            Vendor_Work_Start_Date__c = Date.today(),
            Vendor_Work_End_Date__c = Date.today().addDays(5),
            Completion__c = params.completion
        );
        insert va;

        Task t = new Task(
            Subject = 'Test Task',
            Status = 'Not Started',
            WhatId = va.Id
        );
        insert t;
    }

    // 9. Complex Data: Spec Data
    public static void createSpecData(Id oppId, String category, String productName) {
        Interior_Product__c product = new Interior_Product__c(Name = productName);
        insert product;

        ContentVersion cv = createContentVersion('Spec File ' + productName, 'Test File Content');
        linkFileToRecord(cv.Id, product.Id);

        Project_Specification__c spec = new Project_Specification__c(
            Opportunity__c = oppId,
            Interior_Product__c = product.Id,
            Vendor_Category__c = category
        );
        insert spec;
    }
    // 10. Create Payment Term (Dynamic Parent Linking)
    public static Payment_Term__c createPaymentTerm(Id parentId, String label, Decimal percentage) {
        Payment_Term__c term = new Payment_Term__c(
            Term_Label__c = label,
            Percentage__c = percentage,
            Due_Date__c = Date.today().addDays(15),
            Name = label
        );

        // Dynamically determining parent type
        String sObjName = parentId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            term.Opportunity__c = parentId;
        } else if (sObjName == 'Project__c') {
            term.Project__c = parentId;
        }

        insert term;
        return term;
    }
    // 11. Create Lead
    public static Lead createLead(String lastName) {
        Lead l = new Lead(
            LastName = lastName, 
            Company = 'Test Company', 
            Status = 'Open - Not Contacted' // Adjust based on your Org's picklist
        );
        insert l;
        return l;
    }

    // 12. Create Site Visit Report (Handles RecordType Lookup)
    public static Site_Visit_Report__c createSiteVisitReport(Id parentId, String rtName) {
        // Fetch RecordTypeId by Name to match Controller logic
        Id rtId = Schema.SObjectType.Site_Visit_Report__c
            .getRecordTypeInfosByName()
            .get(rtName)
            .getRecordTypeId();

        Site_Visit_Report__c svr = new Site_Visit_Report__c(
            RecordTypeId = rtId,
            Wizard_Step__c = 1,
            Total_Estimated_Cost__c = 1000 // FIXED: Populating required field
        );

        // Dynamic Parent Linking
        String sObj = parentId.getSObjectType().getDescribe().getName();
        if (sObj == 'Lead') {
            svr.Lead__c = parentId;
        } else if (sObj == 'Opportunity') {
            svr.Opportunity__c = parentId;
        }
        
        insert svr;
        return svr;
    }

    // 13. Create Vendor Opportunity (Simple)
    public static Vendor_Opportunity__c createVendorOpportunity(Id oppId, Id vendorId, String status) {
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = oppId,
            Vendor__c = vendorId,
            Vendor_Opportunity_Status__c = status
        );
        insert vo;
        return vo;
    }

    // 14. Create Custom Quotation
    public static Quotation__c createQuotation(Id oppId, String name) {
        Quotation__c q = new Quotation__c(
            Name = name, // Standard Name field
            Opportunity__c = oppId 
            // Add other required fields here if you have them (e.g. Status__c)
        );
        insert q;
        return q;
    }
}