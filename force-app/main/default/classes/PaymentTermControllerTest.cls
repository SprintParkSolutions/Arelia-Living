@isTest
public class PaymentTermControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User (Supervisor)
        User u = TestDataUtility.createSupervisorUser('paytest');

        // 2. Create Project
        Project__c proj = TestDataUtility.createProject('Test Project Payment');

        // 3. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp Payment', u.Id);

        // 4. Create Initial Payment Terms
        TestDataUtility.createPaymentTerm(proj.Id, 'Project Advance', 20.0);
        TestDataUtility.createPaymentTerm(opp.Id, 'Opp Advance', 10.0);
    }

    @isTest
    static void testGetPaymentTermsForOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(opp.Id);
        Test.stopTest();

        Assert.isNotNull(terms, 'Terms list should not be null');
        Assert.areEqual(1, terms.size(), 'Should return 1 payment term for opportunity');
        Assert.areEqual('Opp Advance', terms[0].Term_Label__c, 'Label should match');
    }

    @isTest
    static void testGetPaymentTermsForProject() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(proj.Id);
        Test.stopTest();

        Assert.isNotNull(terms, 'Terms list should not be null');
        Assert.areEqual(1, terms.size(), 'Should return 1 payment term for project');
        Assert.areEqual('Project Advance', terms[0].Term_Label__c, 'Label should match');
    }

    @isTest
    static void testGetPaymentTermsInvalidId() {
        // Passing a User ID (valid ID format, but unsupported object type)
        User u = [SELECT Id FROM User LIMIT 1];

        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(u.Id);
        Test.stopTest();

        Assert.isNotNull(terms, 'Should return empty list, not null');
        Assert.areEqual(0, terms.size(), 'Should return 0 terms for unsupported object');
    }
    
    @isTest
    static void testGetPaymentTermsNullId() {
        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(null);
        Test.stopTest();

        Assert.areEqual(0, terms.size(), 'Should return 0 terms for null ID');
    }

    @isTest
    static void testSavePaymentTermsInsert() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Create a new term in memory (not inserted yet)
        Payment_Term__c newTerm = new Payment_Term__c(
            Term_Label__c = 'Second Installment',
            Percentage__c = 30.0,
            Due_Date__c = Date.today().addDays(30)
        );

        Test.startTest();
        PaymentTermController.savePaymentTerms(
            new List<Payment_Term__c>{ newTerm }, 
            opp.Id, 
            new List<Id>() // No deletions
        );
        Test.stopTest();

        // Verify insertion
        List<Payment_Term__c> terms = [SELECT Id, Term_Label__c FROM Payment_Term__c WHERE Opportunity__c = :opp.Id];
        Assert.areEqual(2, terms.size(), 'Should have 2 terms now (1 setup + 1 new)');
    }

    @isTest
    static void testSavePaymentTermsUpdate() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Payment_Term__c existingTerm = [SELECT Id, Percentage__c FROM Payment_Term__c WHERE Opportunity__c = :opp.Id LIMIT 1];

        // Modify value
        existingTerm.Percentage__c = 50.0;
        existingTerm.Term_Label__c = 'Updated Label'; // Trigger name update logic

        Test.startTest();
        PaymentTermController.savePaymentTerms(
            new List<Payment_Term__c>{ existingTerm }, 
            opp.Id, 
            new List<Id>()
        );
        Test.stopTest();

        // Verify update
        Payment_Term__c updatedTerm = [SELECT Percentage__c, Name FROM Payment_Term__c WHERE Id = :existingTerm.Id];
        Assert.areEqual(50.0, updatedTerm.Percentage__c, 'Percentage should be updated');
        Assert.areEqual('Updated Label', updatedTerm.Name, 'Name should be synced with Label');
    }

    @isTest
    static void testSavePaymentTermsDelete() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Payment_Term__c existingTerm = [SELECT Id FROM Payment_Term__c WHERE Opportunity__c = :opp.Id LIMIT 1];

        Test.startTest();
        PaymentTermController.savePaymentTerms(
            new List<Payment_Term__c>(), // No inserts/updates
            opp.Id, 
            new List<Id>{ existingTerm.Id } // ID to delete
        );
        Test.stopTest();

        // Verify deletion
        List<Payment_Term__c> terms = [SELECT Id FROM Payment_Term__c WHERE Id = :existingTerm.Id];
        Assert.areEqual(0, terms.size(), 'Record should be deleted');
    }

    @isTest
    static void testSavePaymentTermsException() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        try {
            // Passing NULL as the list of terms will cause a NullPointerException in the for-loop,
            // which the controller catches and re-throws as AuraHandledException.
            PaymentTermController.savePaymentTerms(null, opp.Id, new List<Id>());
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }
}