@isTest
public class ProjectRequestControllerTest {

    @isTest
    static void testGetProjectQuotationTypeValues() {
        Test.startTest();
        
        // Execute the method
        List<String> values = ProjectRequestController.getProjectQuotationTypeValues();
        
        Test.stopTest();
        
        // Assertions
        // Since this returns metadata from the org, we can simply ensure it is not null.
        // Whether it is empty or not depends on the specific org configuration, 
        // so checking != null is the safest robust assertion.
        System.assert(values != null, 'The returned list should never be null');
        
        // Optional: Debug the values to verify in logs
        System.debug('Retrieved Picklist Values: ' + values);
    }
}