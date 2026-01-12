public with sharing class InteriorProjectConfigController {

    @AuraEnabled(cacheable=true)
    public static List<Interior_Project_Config__c> getConfig(Id opportunityId) {

        Opportunity opp = [
            SELECT Interior_Project_Type__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        return [
            SELECT Room_Type__c, Product_Category__c
            FROM Interior_Project_Config__c
            WHERE Interior_Project_Type__c = :opp.Interior_Project_Type__c
            AND Active__c = true
        ];
    }
}