    public with sharing class VendorOpportunityController {

        // Wrapper to send Field Set data to LWC
        public class FieldSetMember {
            @AuraEnabled public String label;
            @AuraEnabled public String fieldPath;
            @AuraEnabled public Boolean required;
            @AuraEnabled public Boolean isEditable; 
        }

        // 1. Fetch Fields from Field Set
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

        // 2. Check if records exist
        @AuraEnabled
        public static Boolean hasExistingRecords(Id opportunityId) {
            return [SELECT Count() FROM Vendor_Opportunity__c WHERE Opportunity__c = :opportunityId] > 0;
        }

        // 3. Create Records (Enforces Opportunity Link)
        @AuraEnabled
        public static List<Vendor_Opportunity__c> createVendorOpportunities(List<Vendor_Opportunity__c> records, Id opportunityId) {
            for(Vendor_Opportunity__c vo : records) {
                vo.Opportunity__c = opportunityId; // Hard-code link for security
            }
            insert records;
            return records;
        }

        // 4. Get Existing Records for Preview
        @AuraEnabled
        public static List<Vendor_Opportunity__c> getExistingRecords(Id opportunityId, List<String> queryFields) {
            if(!queryFields.contains('Id')) queryFields.add('Id');
            
            // Sanitize queryFields to avoid injection if needed, though simpler here
            String query = 'SELECT ' + String.join(queryFields, ',') + 
                        ' FROM Vendor_Opportunity__c WHERE Opportunity__c = :opportunityId';
            return Database.query(query);
        }

        // 5. Move Files from Opportunity to Vendor_Opportunity__c
        @AuraEnabled
        public static void reparentFiles(Map<String, String> fileMap) {
            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            
            // Loop through the map: Key = DocId, Value = VendorOpportunityId
            for(String docId : fileMap.keySet()) {
                ContentDocumentLink newLink = new ContentDocumentLink();
                newLink.ContentDocumentId = docId; // The file
                newLink.LinkedEntityId = fileMap.get(docId); // The new Vendor Opportunity
                newLink.ShareType = 'V'; // 'V' = Viewer, 'I' = Inferred. 'V' is safest for new links.
                linksToInsert.add(newLink);
            }
            
            if(!linksToInsert.isEmpty()) {
                insert linksToInsert;
            }
        }

        // Add this new method to your existing Class
    @AuraEnabled
    public static Map<Id, String> getAttachedFileNames(List<Id> parentIds) {
        Map<Id, String> fileMap = new Map<Id, String>();
        
        // Query ContentDocumentLink to find files linked to these records
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :parentIds 
            ORDER BY SystemModstamp DESC
        ];

        // Map Parent ID to File Name (taking the most recent one if multiple exist)
        for(ContentDocumentLink link : links) {
            if(!fileMap.containsKey(link.LinkedEntityId)) {
                fileMap.put(link.LinkedEntityId, link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension);
            }
        }
        return fileMap;
    }
    }