public with sharing class InventoryApiService {

    @AuraEnabled(cacheable=true)
    public static List<Interior_Product__c> getProducts(String roomType, String category) {
        return [
            SELECT Id, Name, Product_Category__c, Room_Type__c,
                   Unit_Price__c,
                   (SELECT Id, ContentDocument.LatestPublishedVersionId FROM ContentDocumentLinks LIMIT 1)
            FROM Interior_Product__c
            WHERE Room_Type__c = :roomType
            AND Product_Category__c = :category
            ORDER BY Name
        ];
    }
}