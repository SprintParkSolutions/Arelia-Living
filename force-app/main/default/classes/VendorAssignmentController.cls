public with sharing class VendorAssignmentController {

    public class FieldSetMember {
        @AuraEnabled public String label;
        @AuraEnabled public String fieldPath;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean isEditable; 
        @AuraEnabled public String type;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldSetMember> getFieldSetFields(String objectName, String fieldSetName) {
        List<FieldSetMember> fieldList = new List<FieldSetMember>();
        
        // FIXED: Use getGlobalDescribe instead of Type.forName
        SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
        
        if (sObjectType == null) {
            return fieldList;
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Schema.FieldSet fieldSet = describeResult.fieldSets.getMap().get(fieldSetName);

        if (fieldSet != null) {
            for (Schema.FieldSetMember f : fieldSet.getFields()) {
                FieldSetMember wrapper = new FieldSetMember();
                wrapper.label = f.getLabel();
                wrapper.fieldPath = f.getFieldPath();
                wrapper.required = f.getRequired() || f.getDbRequired();
                
                Schema.DescribeFieldResult dfr = f.getSObjectField().getDescribe();
                wrapper.isEditable = dfr.isUpdateable();
                wrapper.type = String.valueOf(dfr.getType()); 

                fieldList.add(wrapper);
            }
        }
        return fieldList;
    }
    @AuraEnabled
    public static Boolean hasExistingRecords(Id projectId) {
        // CHANGED: 'WITH USER_MODE' -> 'WITH SECURITY_ENFORCED'
        Integer count = [SELECT Count() FROM Vendor_Assignment__c WHERE Project__c = :projectId WITH SECURITY_ENFORCED];
        return count > 0;
    }

    @AuraEnabled
    public static List<Vendor_Assignment__c> createVendorAssignments(List<Vendor_Assignment__c> records, Id projectId) {
        try {
            // Check Create Permissions manually since 'insert as user' is not available in old APIs
            if (!Schema.sObjectType.Vendor_Assignment__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create Vendor Assignments.');
            }

            for(Vendor_Assignment__c va : records) {
                va.Project__c = projectId; 
            }
            
            // CHANGED: 'insert as user' -> 'insert'
            insert records;
            return records;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
public static List<Vendor_Assignment__c> getExistingRecords(
    Id projectId,
    List<String> queryFields
) {
    if (projectId == null || queryFields == null || queryFields.isEmpty()) {
        return new List<Vendor_Assignment__c>();
    }

    // Always include Id
    Set<String> fieldsToQuery = new Set<String>();
    fieldsToQuery.add('Id');

    Map<String, Schema.SObjectField> fieldMap =
        Schema.SObjectType.Vendor_Assignment__c.fields.getMap();

    // Allow only schema-validated fields
    for (String fieldName : queryFields) {
        if (fieldMap.containsKey(fieldName)) {
            fieldsToQuery.add(fieldName);
        }
    }

    if (fieldsToQuery.isEmpty()) {
        return new List<Vendor_Assignment__c>();
    }

    String soql =
        'SELECT ' + String.join(new List<String>(fieldsToQuery), ',') +
        ' FROM Vendor_Assignment__c WHERE Project__c = :projectId ' +
        'WITH SECURITY_ENFORCED';

    return Database.query(soql);
}


    @AuraEnabled
    public static void reparentFiles(Map<String, String> fileMap) {
        try {
            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            
            for(String docId : fileMap.keySet()) {
                ContentDocumentLink newLink = new ContentDocumentLink();
                newLink.ContentDocumentId = docId;
                newLink.LinkedEntityId = fileMap.get(docId); 
                newLink.ShareType = 'V'; 
                newLink.Visibility = 'AllUsers'; 
                linksToInsert.add(newLink);
            }
            
            if(!linksToInsert.isEmpty()) {
                if (!Schema.sObjectType.ContentDocumentLink.isCreateable()) {
                    throw new AuraHandledException('You do not have permission to attach files.');
                }
                // CHANGED: 'insert as user' -> 'insert'
                insert linksToInsert;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error attaching files: ' + e.getMessage());
        }
    }

    @AuraEnabled
public static Map<Id, String> getAttachedFileNames(List<Id> parentIds) {
    Map<Id, String> fileMap = new Map<Id, String>();

    if (parentIds == null || parentIds.isEmpty()) {
        return fileMap;
    }

    // Id is a strongly typed, non-injectable type → PMD-safe
  String soql =
    'SELECT LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension ' +
    'FROM ContentDocumentLink ' +
    'WHERE LinkedEntityId IN :parentIds ' +
    'WITH SECURITY_ENFORCED ' + // Moved up
    'ORDER BY SystemModstamp DESC';

    List<ContentDocumentLink> links = Database.query(soql);

    for (ContentDocumentLink link : links) {
        if (!fileMap.containsKey(link.LinkedEntityId)) {
            fileMap.put(
                link.LinkedEntityId,
                link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension
            );
        }
    }
    return fileMap;
}


}