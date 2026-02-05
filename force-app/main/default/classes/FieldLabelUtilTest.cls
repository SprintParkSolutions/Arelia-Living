/**
 * @description Test class for FieldLabelUtil to ensure field labels are retrieved correctly.
 * PMD violations addressed: Class naming, commenting, and assertion usage.
 */
@isTest
private class FieldLabelUtilTest {

    /**
     * @description Validates that the utility correctly retrieves the label for a standard Lead field.
     * This also tests the lazy initialization (first time call).
     */
    @isTest
    static void testGetLeadLabelValidField() {
        // Prepare data using the provided Utility Class
        TestDataUtility.createLead('Test Label Lead');

        Test.startTest();
        // 'company' is a standard field on Lead. Labels are case-insensitive in the Map keyset.
        String label = FieldLabelUtil.getLeadLabel('company');
        Test.stopTest();

        // Assertions
        Assert.areNotEqual(null, label, 'The label for Company field should not be null');
        Assert.areEqual('Company', label, 'The label should match the standard Lead Company label');
    }

    /**
     * @description Validates that the utility returns null for a field API name that does not exist.
     */
    @isTest
    static void testGetLeadLabelInvalidField() {
        Test.startTest();
        String label = FieldLabelUtil.getLeadLabel('Non_Existent_Field_XYZ__c');
        Test.stopTest();

        // Assertions
        Assert.areEqual(null, label, 'The label for a non-existent field should be null');
    }

    /**
     * @description Validates that the static map is reused (Singleton/Caching logic)
     * and handles case sensitivity based on how Schema.getMap() keys are stored (lowercase).
     */
    @isTest
    static void testGetLeadLabelCaching() {
        // First call populates the map
        String labelFirstCall = FieldLabelUtil.getLeadLabel('lastname');
        
        Test.startTest();
        // Second call uses the cached map
        String labelSecondCall = FieldLabelUtil.getLeadLabel('lastname');
        Test.stopTest();

        Assert.areEqual(labelFirstCall, labelSecondCall, 'The cached result should match the first call');
        Assert.areEqual('Last Name', labelSecondCall, 'The label for LastName should be Last Name');
    }
}