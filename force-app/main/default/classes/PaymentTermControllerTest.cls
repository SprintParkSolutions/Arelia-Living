/**
 * @description Comprehensive test class for PaymentTermController to achieve 90%+ coverage.
 * PMD Violations addressed: No hardcoded IDs, Modern Assertions, Proper Scoping.
 */
@isTest
private class PaymentTermControllerTest {

    @testSetup
    static void setup() {
        User u = TestDataUtility.createSupervisorUser('paytest');
        System.runAs(u) {
            Contact con = TestDataUtility.createContact('Test Contact', 'test@pay.com', 'pass123');
            Project__c proj = TestDataUtility.createProject('Test Project Payment', 10000, con.Id);
            Opportunity opp = TestDataUtility.createOpportunity('Test Opp Payment', u.Id);

            TestDataUtility.createPaymentTerm(proj.Id, 'Project Advance', 20.0);
            TestDataUtility.createPaymentTerm(opp.Id, 'Opp Advance', 10.0);
        }
    }

    @isTest
    static void testGetPaymentTermsForOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(opp.Id);
        Test.stopTest();
        Assert.areEqual(1, terms.size(), 'Should return 1 term for Opportunity');
    }

    @isTest
    static void testGetPaymentTermsForProject() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(proj.Id);
        Test.stopTest();
        Assert.areEqual(1, terms.size(), 'Should return 1 term for Project');
    }

    @isTest
    static void testGetPaymentTermsInvalidLogic() {
        // Covering the 'else' branch in getPaymentTerms (unsupported SObject)
        User u = [SELECT Id FROM User WHERE Alias = 'paytest' LIMIT 1];
        Test.startTest();
        List<Payment_Term__c> terms = PaymentTermController.getPaymentTerms(u.Id);
        Test.stopTest();
        Assert.areEqual(0, terms.size(), 'Should return empty list for unsupported SObject');
    }

    @isTest
    static void testSavePaymentTermsForProject() {
        // Covering the 'Project__c' logic branch in savePaymentTerms
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        List<Payment_Term__c> terms = new List<Payment_Term__c>{
            new Payment_Term__c(Term_Label__c = 'Project Milestone', Percentage__c = 50)
        };

        Test.startTest();
        PaymentTermController.savePaymentTerms(terms, proj.Id, new List<Id>());
        Test.stopTest();

        Payment_Term__c check = [SELECT Name, Project__c FROM Payment_Term__c WHERE Term_Label__c = 'Project Milestone' LIMIT 1];
        Assert.areEqual(proj.Id, check.Project__c, 'Should be linked to Project');
        Assert.areEqual('Project Milestone', check.Name, 'Name should be synced from Label');
    }

    @isTest
    static void testSavePaymentTermsForOpportunity() {
        // Covering the 'Opportunity' logic branch in savePaymentTerms
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Payment_Term__c> terms = new List<Payment_Term__c>{
            new Payment_Term__c(Term_Label__c = 'Opp Milestone', Percentage__c = 50)
        };

        Test.startTest();
        PaymentTermController.savePaymentTerms(terms, opp.Id, new List<Id>());
        Test.stopTest();

        Payment_Term__c check = [SELECT Opportunity__c FROM Payment_Term__c WHERE Term_Label__c = 'Opp Milestone' LIMIT 1];
        Assert.areEqual(opp.Id, check.Opportunity__c, 'Should be linked to Opportunity');
    }

    @isTest
    static void testSavePaymentTermsDeletion() {
        // Covering the deletion branch
        Payment_Term__c term = [SELECT Id FROM Payment_Term__c LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        PaymentTermController.savePaymentTerms(new List<Payment_Term__c>(), opp.Id, new List<Id>{term.Id});
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Payment_Term__c WHERE Id = :term.Id];
        Assert.areEqual(0, count, 'Record should be deleted');
    }

    @isTest
    static void testGetPaymentTermsByProjectName() {
        // Covering the required REST-related method in the controller
        Test.startTest();
        List<PaymentTermDTO> results = PaymentTermController.getPaymentTermsByProjectName('Test Project Payment');
        Test.stopTest();
        Assert.isTrue(results.size() > 0, 'Should return DTOs for the project name');
    }

    @isTest
    static void testSavePaymentTermsException() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        
        // Force a DML failure by passing a list with a null element
        // This ensures the code enters the 'catch' block
        List<Payment_Term__c> failList = new List<Payment_Term__c>{ (Payment_Term__c)null };

        Test.startTest();
        try {
            PaymentTermController.savePaymentTerms(failList, opp.Id, null);
            Assert.fail('Expected exception was not thrown');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('Script-thrown exception') || e.getMessage().contains('Error'), 
                'Should catch and rethrow as AuraHandledException');
        }
        Test.stopTest();
    }
}