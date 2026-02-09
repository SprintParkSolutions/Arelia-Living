/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class PaymentTermAuthRestTest {

    @testSetup
    static void setup() {
        User testUser = TestDataUtility.createSupervisorUser('pauth');
        System.runAs(testUser) {
            Contact con = TestDataUtility.createContact('Tester', 'test@test.com', '12345');
            Project__c proj = TestDataUtility.createProject('Mobile Project', 10000, con.Id);
            TestDataUtility.createPaymentTerm(proj.Id, 'Deposit', 20.0);
            
            Opportunity opp = TestDataUtility.createOpportunity('Sales Opp', testUser.Id);
            TestDataUtility.createPaymentTerm(opp.Id, 'Final', 80.0);
        }
    }

    @isTest
    static void testRestEndpointSuccess() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/payment-terms-auth';
        req.httpMethod = 'POST';
        
        Map<String, String> payload = new Map<String, String>{ 'projectName' => 'Mobile Project' };
        req.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = req;

        Test.startTest();
        List<PaymentTermDTO> result = PaymentTermAuthRest.getTerms();
        Test.stopTest();

        Assert.areNotEqual(null, result, 'List should be initialized');
        Assert.isTrue(result.size() > 0, 'Expected terms for the project');
    }

    @isTest
    static void testControllerGetters() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        List<Payment_Term__c> oppTerms = PaymentTermController.getPaymentTerms(opp.Id);
        List<Payment_Term__c> projTerms = PaymentTermController.getPaymentTerms(proj.Id);
        List<Payment_Term__c> nullTerms = PaymentTermController.getPaymentTerms(null);
        Test.stopTest();

        Assert.areEqual(1, oppTerms.size());
        Assert.areEqual(1, projTerms.size());
        Assert.areEqual(0, nullTerms.size());
    }

    @isTest
    static void testControllerSaveAndDelete() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Payment_Term__c existingTerm = [SELECT Id FROM Payment_Term__c WHERE Project__c = :proj.Id LIMIT 1];

        List<Payment_Term__c> toSave = new List<Payment_Term__c>{
            new Payment_Term__c(Term_Label__c = 'Milestone 2', Percentage__c = 30)
        };

        Test.startTest();
        PaymentTermController.savePaymentTerms(toSave, proj.Id, new List<Id>{existingTerm.Id});
        Test.stopTest();

        List<Payment_Term__c> afterSave = [SELECT Id FROM Payment_Term__c WHERE Project__c = :proj.Id];
        // One deleted, one added, total remains 1
        Assert.areEqual(1, afterSave.size());
    }

    /**
     * @description Test catch block coverage. 
     * We pass an invalid list to trigger a DML exception which the controller catches.
     */
   @isTest
    static void testSaveErrorHandling() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        
        // We pass a list with a null element. 
        // This is a guaranteed way to trigger a DML Exception in the Controller's upsert.
        List<Payment_Term__c> invalidTerms = new List<Payment_Term__c>{ (Payment_Term__c)null }; 

        Test.startTest();
        try {
            // This will enter the 'savePaymentTerms' method, hit 'upsert', and jump to 'catch'
            PaymentTermController.savePaymentTerms(invalidTerms, proj.Id, null);
            
            // If it doesn't throw, we fail the test
            Assert.fail('The method should have thrown an AuraHandledException');
        } catch (Exception e) {
            // We catch the exception and verify it's the one we threw
            // In tests, AuraHandledException often reports as 'Script-thrown exception'
            Assert.isNotNull(e.getMessage(), 'An error message should be present');
        }
        Test.stopTest();
    }
    }