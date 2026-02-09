/**
 * @description Controller for Payment Term operations.
 * PMD: Suppressing VariableNamingConventions for local underscore variables if necessary.
 */
public without sharing class PaymentTermController {
    
    /**
     * @description Required by PaymentTermAuthRest. Fetches terms by Project Name.
     * @param projectName Name of the project
     * @return List of PaymentTermDTO
     */
    // Inside PaymentTermController.cls
    public static List<PaymentTermDTO> getPaymentTermsByProjectName(String projectName) {
        List<PaymentTermDTO> results = new List<PaymentTermDTO>();
        List<Payment_Term__c> terms = [
        SELECT Id, Name, Term_Label__c, Percentage__c, Due_Date__c, Payment_Received__c 
        FROM Payment_Term__c 
        WHERE Project__r.Name = :projectName
        ORDER BY Due_Date__c ASC
    ];
        for (Payment_Term__c term : terms) {
            results.add(new PaymentTermDTO(term));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<Payment_Term__c> getPaymentTerms(Id recordId) {
        if (recordId == null) {
            return new List<Payment_Term__c>();
        }

        String sObjName = recordId.getSObjectType().getDescribe().getName();
        String query = 'SELECT Id, Name, Term_Label__c, Percentage__c, Due_Date__c, Payment_Received__c FROM Payment_Term__c ';

        if (sObjName == 'Opportunity') {
            query += 'WHERE Opportunity__c = :recordId ';
        } else if (sObjName == 'Project__c') {
            query += 'WHERE Project__c = :recordId ';
        } else {
            return new List<Payment_Term__c>();
        }

        query += 'ORDER BY Due_Date__c ASC';
        return Database.query(String.escapeSingleQuotes(query));
    }

    @AuraEnabled
    public static void savePaymentTerms(List<Payment_Term__c> terms, Id recordId, List<Id> termsToDelete) {
        try {
            if (termsToDelete != null && !termsToDelete.isEmpty()) {
                delete [SELECT Id FROM Payment_Term__c WHERE Id IN :termsToDelete];
            }

            if (terms == null || recordId == null) {
                return;
            }

            String sObjName = recordId.getSObjectType().getDescribe().getName();

            for (Payment_Term__c term : terms) {
                if (sObjName == 'Opportunity') {
                    term.Opportunity__c = recordId;
                } else if (sObjName == 'Project__c') {
                    term.Project__c = recordId;
                }
                
                if (String.isNotBlank(term.Term_Label__c)) {
                    term.Name = term.Term_Label__c;
                }
            }
            upsert terms;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving terms: ' + e.getMessage());
        }
    }
}