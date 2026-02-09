/**
 * @description Test class for SupervisorLeadFilesController
 * Covers the GET method for retrieving files associated with a Lead.
 */
@isTest
private class SupervisorLeadFilesControllerTest {

    @testSetup
    static void setup() {
        // Create a Lead using the utility
        Lead testLead = TestDataUtility.createLead('Doe');

        // Create a File (ContentVersion)
        ContentVersion cv = TestDataUtility.createContentVersion('TestFile', 'Hello World');

        // Link File to the Lead
        TestDataUtility.linkFileToRecord(cv.Id, testLead.Id);
    }

    /**
     * @description Validates that the getFiles method returns the correct file data.
     */
    @isTest
    static void testGetFilesSuccess() {
        Lead ld = [SELECT Id FROM Lead LIMIT 1];

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        // Mapping the URI correctly
        req.requestURI = '/services/apexrest/supervisor/leadfiles/' + ld.Id;
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadFilesController.getFiles();
        Test.stopTest();

        // FIX: Check responseBody instead of statusCode (which is null unless explicitly set in code)
        System.assertNotEquals(null, res.responseBody, 'Response body should not be null');
        
        List<SupervisorLeadFilesController.FileDTO> results = 
            (List<SupervisorLeadFilesController.FileDTO>) JSON.deserialize(
                res.responseBody.toString(), 
                List<SupervisorLeadFilesController.FileDTO>.class
            );

        System.assertEquals(1, results.size(), 'There should be one file linked to the lead');
        System.assertEquals('TestFile', results[0].title, 'The file title should match the setup data');
    }

    @isTest
    static void testGetFilesNoResults() {
        Lead emptyLead = TestDataUtility.createLead('NoFiles');

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/supervisor/leadfiles/' + emptyLead.Id;
        req.httpMethod = 'GET';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadFilesController.getFiles();
        Test.stopTest();

        List<SupervisorLeadFilesController.FileDTO> results = 
            (List<SupervisorLeadFilesController.FileDTO>) JSON.deserialize(
                res.responseBody.toString(), 
                List<SupervisorLeadFilesController.FileDTO>.class
            );

        System.assertEquals(0, results.size(), 'Results list should be empty for a lead with no files');
    }
}