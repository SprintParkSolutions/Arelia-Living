public with sharing class VendorAssignmentController {

    public class FieldSetMember {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldPath;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean isEditable; 
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldSetMember> getFieldSetFields(String objectName, String fieldSetName) {
        List<FieldSetMember> fieldList = new List<FieldSetMember>();
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
        
        if (sObjectType == null) return fieldList;

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Schema.FieldSet fieldSet = describeResult.fieldSets.getMap().get(fieldSetName);

        if (fieldSet != null) {
            for (Schema.FieldSetMember f : fieldSet.getFields()) {
                FieldSetMember wrapper = new FieldSetMember();
                wrapper.label = f.getLabel();
                wrapper.fieldPath = f.getFieldPath();
                wrapper.required = f.getRequired() || f.getDbRequired();
                fieldList.add(wrapper);
            }
        }
        return fieldList;
    }

    @AuraEnabled
    public static Boolean hasExistingRecords(Id projectId) {
        return [SELECT Count() FROM Vendor_Assignment__c WHERE Project__c = :projectId] > 0;
    }

    @AuraEnabled
    public static List<Vendor_Assignment__c> createVendorAssignments(List<Vendor_Assignment__c> records, Id projectId) {
        // We re-enforce the Project ID here for security, 
        // but Supervisor/Opportunity are passed within the 'records' list from LWC
        for(Vendor_Assignment__c va : records) {
            va.Project__c = projectId; 
        }
        insert records;
        return records;
    }

    @AuraEnabled
    public static List<Vendor_Assignment__c> getExistingRecords(Id projectId, List<String> queryFields) {
        if(!queryFields.contains('Id')) queryFields.add('Id');
        
        // Dynamic SOQL to get fields defined in the Preview Field Set
        String query = 'SELECT ' + String.join(queryFields, ',') + 
                       ' FROM Vendor_Assignment__c WHERE Project__c = :projectId';
        return Database.query(query);
    }

    @AuraEnabled
    public static void reparentFiles(Map<String, String> fileMap) {
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        
        for(String docId : fileMap.keySet()) {
            ContentDocumentLink newLink = new ContentDocumentLink();
            newLink.ContentDocumentId = docId;
            newLink.LinkedEntityId = fileMap.get(docId); // The new Vendor Assignment ID
            newLink.ShareType = 'V'; 
            linksToInsert.add(newLink);
        }
        
        if(!linksToInsert.isEmpty()) {
            insert linksToInsert;
        }
    }

    @AuraEnabled
    public static Map<Id, String> getAttachedFileNames(List<Id> parentIds) {
        Map<Id, String> fileMap = new Map<Id, String>();
        
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :parentIds 
            ORDER BY SystemModstamp DESC
        ];

        for(ContentDocumentLink link : links) {
            if(!fileMap.containsKey(link.LinkedEntityId)) {
                fileMap.put(link.LinkedEntityId, link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension);
            }
        }
        return fileMap;
    }
}