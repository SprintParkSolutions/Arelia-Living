/**
 * @name        Arelia_ManualProjectRequestController
 * @description This Apex class provides backend logic for the IDC Home Page, 
 *              including fetching the Arelia notification email from custom metadata 
 *              and creating Lead records based on user-submitted information.
 *              Designed for use with Lightning Web Component.
 * @author      
 * @createdDate 
 * @company     Arelia Living
 * @version     1.0
 */
public without sharing class Arelia_ManualProjectRequestController {

    /**
     * @description Creates a new Lead record in the system using the provided field values.
     *              This method is used when a user submits the IDC contact form, allowing
     *              data to be stored and processed as a Lead.
     *
     * @param firstName         The first name of the lead.
     * @param lastName          The last name of the lead.
     * @param email             The email address of the lead.
     * @param phone             The phone number of the lead.
     * @param company           The company or organization name.
     * @param budget            The estimated budget for the project.
     * @param projectDescription A brief description of the project.
     * @param siteLocation     The site location of the project.
     * @param typeOfProject     The type of project being requested (custom picklist).
     * @param projectScope      The scope of the project (custom picklist).
     * @return                  The ID of the newly created Lead record.
     * @throws                  AuraHandledException If DML operation fails or another unexpected error occurs.
     */
    @AuraEnabled(cacheable=true)
    public static Lead getLeadById(Id leadId) {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Email, Phone, Company, Customer_Budget__c, 
                   Type_Of_Project__c, Project_Scope__c, Project_Description__c, Site_Location__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        
        if (!leads.isEmpty()) {
            return leads[0];
        }
        return null; // No lead found
    }

    @AuraEnabled
    public static void updateLead(
        Id leadId,
        String firstName, 
        String lastName, 
        String email, 
        String phone, 
        String typeOfProject, 
        String projectScope,
        String company, 
        Decimal budget, 
        String projectDescription,
        String siteLocation
    ) {
        Lead existingLead = [SELECT Id FROM Lead WHERE Id = :leadId LIMIT 1];

        existingLead.FirstName = firstName;
        existingLead.LastName = lastName;
        existingLead.Email = email;
        existingLead.Phone = phone;
        existingLead.Type_Of_Project__c = typeOfProject;
        existingLead.Project_Scope__c = projectScope;
        existingLead.Company = company;
        existingLead.Customer_Budget__c = budget;
        existingLead.Project_Description__c = projectDescription;
        existingLead.Site_Location__c = siteLocation;

        update existingLead;
    }
}