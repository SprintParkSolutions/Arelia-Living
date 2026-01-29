/**
 * @FileName    : ProjectRequestController.cls
 * @description : Provides helper methods for the Project Request wizard
 *                (quotation type picklist).
 */
public without sharing class ProjectRequestController {

    /**
     * @description Returns the available picklist values for
     *              Lead.Project_Request_Quotation_Type__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getProjectQuotationTypeValues() {
        List<String> values = new List<String>();

        Schema.DescribeFieldResult fieldResult =
            Lead.Project_Request_Quotation_Type__c.getDescribe();

        for (Schema.PicklistEntry picklistValue : fieldResult.getPicklistValues()) {
            values.add(picklistValue.getLabel());
        }
        return values;
    }
}