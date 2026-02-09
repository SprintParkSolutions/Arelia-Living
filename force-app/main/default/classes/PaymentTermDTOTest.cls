/**
 * @description       : Test class for PaymentTermDTO to ensure 100% coverage and PMD compliance.
 * @author            : Gemini
 * @group             : Test Classes
 * @last modified on  : 02-05-2026
**/
@isTest
private class PaymentTermDTOTest {

    /**
     * @description Tests the default constructor to ensure manual property assignment works.
     */
    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
        PaymentTermDTO dto = new PaymentTermDTO();
        dto.termId = 'a01xx0000000001';
        dto.label = 'Initial Deposit';
        dto.percentage = 10.5;
        dto.dueDate = Date.today();
        dto.paymentReceived = true;
        Test.stopTest();

        Assert.areEqual('a01xx0000000001', dto.termId, 'Term ID should match assigned value');
        Assert.areEqual('Initial Deposit', dto.label, 'Label should match assigned value');
        Assert.areEqual(10.5, dto.percentage, 'Percentage should match assigned value');
        Assert.areEqual(true, dto.paymentReceived, 'Payment status should match assigned value');
    }

    /**
     * @description Tests the parameterized constructor using the provided TestDataUtility.
     */
    @isTest
    static void testSObjectConstructor() {
        // 1. Setup data using Utility Class
        // We need a parent record for the Payment Term. Creating an Account for simplicity.
        Account acc = TestDataUtility.createAccount('Test Account');
        
        // 2. Create the Payment Term record
        Payment_Term__c term = TestDataUtility.createPaymentTerm(acc.Id, 'Milestone 1', 25.0);
        
        // Manually update fields not covered by the utility if necessary
        term.Payment_Received__c = true;
        update term;

        // 3. Re-query to get all fields required by the DTO constructor
        Payment_Term__c queriedTerm = [
            SELECT Id, Term_Label__c, Percentage__c, Due_Date__c, Payment_Received__c 
            FROM Payment_Term__c 
            WHERE Id = :term.Id 
            LIMIT 1
        ];

        // 4. Execution
        Test.startTest();
        PaymentTermDTO dto = new PaymentTermDTO(queriedTerm);
        Test.stopTest();

        // 5. Assertions
        Assert.areNotEqual(null, dto, 'DTO instance should not be null');
        Assert.areEqual(queriedTerm.Id, dto.termId, 'Term ID mapping failed');
        Assert.areEqual(queriedTerm.Term_Label__c, dto.label, 'Label mapping failed');
        Assert.areEqual(queriedTerm.Percentage__c, dto.percentage, 'Percentage mapping failed');
        Assert.areEqual(queriedTerm.Due_Date__c, dto.dueDate, 'Due Date mapping failed');
        Assert.areEqual(queriedTerm.Payment_Received__c, dto.paymentReceived, 'Payment Received mapping failed');
    }
}