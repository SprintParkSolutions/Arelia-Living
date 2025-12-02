/**
* @description  Returns the available picklist values for Lead.Project_Request_Quotation_Type__c.
*/

public without sharing class ProjectRequestController {
    @AuraEnabled(cacheable=true)
    public static List<String> getProjectQuotationTypeValues() {
        List<String> values = new List<String>();

        // Describe the picklist fields
        Schema.DescribeFieldResult fieldResult = Lead.Project_Request_Quotation_Type__c.getDescribe();
        
        // Extract values
        for (Schema.PicklistEntry picklistValue : fieldResult.getPicklistValues()) {
            values.add(picklistValue.getLabel());
        }

        return values;
    }
}