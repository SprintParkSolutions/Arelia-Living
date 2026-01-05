public with sharing class SVRWizardController {

    /* ========== GET LATEST SVR (Strict Record Type Check) ========== */
    @AuraEnabled
    public static Site_Visit_Report__c getLatestSVR(Id parentId, String objectApiName) {
        if (parentId == null) return null;

        // 1. Determine the STRICT Record Type we are looking for
        String targetRtName = '';
        if (objectApiName == 'Lead') {
            targetRtName = 'Lead Site Visit Report';
        } else if (objectApiName == 'Opportunity') {
            targetRtName = 'Opportunity Site Visit Report';
        } else {
            return null; // Unsupported object
        }

        // 2. Build Query with RecordType Filter
        String query = 'SELECT Id, Wizard_Step__c, Is_Final_Submitted__c, Layout_Blueprint_Uploaded__c, Management_Approval__c ' +
                       'FROM Site_Visit_Report__c ' + 
                       'WHERE RecordType.Name = :targetRtName '; // <--- STRICT CHECK

        // 3. Add Parent Filter
        if (objectApiName == 'Lead') {
            query += 'AND Lead__c = :parentId ';
        } else if (objectApiName == 'Opportunity') {
            query += 'AND Opportunity__c = :parentId ';
        }

        query += 'ORDER BY CreatedDate DESC LIMIT 1';

        List<Site_Visit_Report__c> svrs = Database.query(query);
        return svrs.isEmpty() ? null : svrs[0];
    }

    /* ========== CREATE SVR (Unchanged, but benefits from stricter check) ========== */
    @AuraEnabled
    public static Id createSVR(Id parentId, String objectApiName, Site_Visit_Report__c draftData) {
        
        // 1. Double check using the new strict logic
        Site_Visit_Report__c existing = getLatestSVR(parentId, objectApiName);
        if (existing != null) return existing.Id;

        String rtName = '';
        if (objectApiName == 'Lead') {
            draftData.Lead__c = parentId;
            rtName = 'Lead Site Visit Report';
        } else if (objectApiName == 'Opportunity') {
            draftData.Opportunity__c = parentId;
            rtName = 'Opportunity Site Visit Report';
        }

        if (String.isNotBlank(rtName)) {
            try {
                draftData.RecordTypeId = Schema.SObjectType.Site_Visit_Report__c
                    .getRecordTypeInfosByName()
                    .get(rtName)
                    .getRecordTypeId();
            } catch (Exception e) {
                throw new AuraHandledException('Record Type "' + rtName + '" not found.');
            }
        }

        draftData.Wizard_Step__c = 2;
        insert draftData;
        return draftData.Id;
    }

    /* ========== SAVE STEP ========== */
    @AuraEnabled
    public static void saveStep(Id svrId, Integer stepNo) {
        update new Site_Visit_Report__c(Id = svrId, Wizard_Step__c = stepNo);
    }

    /* ========== SAVE DRAFT ========== */
    @AuraEnabled
    public static void saveDraft(Site_Visit_Report__c data) {
        update data;
    }

    /* ========== MARK BLUEPRINT ========== */
    @AuraEnabled
    public static void markBlueprintUploaded(Id svrId) {
        update new Site_Visit_Report__c(Id = svrId, Layout_Blueprint_Uploaded__c = true);
    }

    /* ========== FINAL SUBMIT ========== */
    @AuraEnabled
    public static void finalSubmit(Id svrId) {
        update new Site_Visit_Report__c(
            Id = svrId,
            Wizard_Step__c = 3,
            Is_Final_Submitted__c = true,
            Site_Visit_Report_Status__c = 'Approved' 
        );
    }

    /* ========== UTILS ========== */
    @AuraEnabled(cacheable=true)
    public static List<String> getFieldSetFields(String objectApi, String fieldSetName) {
        List<String> fields = new List<String>();
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApi);
        if(t == null) return fields;
        
        Schema.DescribeSObjectResult describe = t.getDescribe();
        if(describe.fieldSets.getMap().containsKey(fieldSetName)) {
            Schema.FieldSet fs = describe.fieldSets.getMap().get(fieldSetName);
            for (Schema.FieldSetMember f : fs.getFields()) {
                fields.add(f.getFieldPath());
            }
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContentDocumentLink> getFiles(Id recordId) {
        return [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];
    }
}