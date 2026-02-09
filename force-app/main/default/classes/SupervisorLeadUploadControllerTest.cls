/**
 * @description Test class for SupervisorLeadUploadController
 * Provides coverage for file uploading and linking to Lead records via REST API.
 */
@isTest
private class SupervisorLeadUploadControllerTest {

    @testSetup
    static void setup() {
        // Create a Lead using the provided utility
        TestDataUtility.createLead('TestLeadUpload');
    }

    /**
     * @description Tests a successful file upload scenario with multiple files.
     */
    @isTest
    static void testUploadSuccess() {
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        
        // Prepare Payload
        List<SupervisorLeadUploadController.FilePayload> payload = new List<SupervisorLeadUploadController.FilePayload>();
        
        SupervisorLeadUploadController.FilePayload file1 = new SupervisorLeadUploadController.FilePayload();
        file1.fileName = 'testFile1.pdf';
        file1.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Content 1'));
        payload.add(file1);

        SupervisorLeadUploadController.FilePayload file2 = new SupervisorLeadUploadController.FilePayload();
        file2.fileName = 'testFile2.jpg';
        file2.base64Data = EncodingUtil.base64Encode(Blob.valueOf('Content 2'));
        payload.add(file2);

        String jsonBody = JSON.serialize(payload);

        // Setup RestContext
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/supervisor/lead/upload/' + testLead.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonBody);

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadUploadController.upload();
        Test.stopTest();

        // Verification
        Assert.areNotEqual(null, res.responseBody, 'Response body should not be null');
        
        SupervisorLeadUploadController.UploadResponse result = 
            (SupervisorLeadUploadController.UploadResponse)JSON.deserialize(
                res.responseBody.toString(), 
                SupervisorLeadUploadController.UploadResponse.class
            );

        Assert.isTrue(result.success, 'The upload should be successful');
        Assert.areEqual(2, result.uploaded, 'Two files should have been uploaded');
        
        // Check if ContentDocumentLinks were created
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testLead.Id];
        // Note: 1 link might already exist if Lead creation creates one, but we expect at least 2 from our upload
        Assert.isTrue(links.size() >= 2, 'There should be at least 2 files linked to the Lead');
    }

    /**
     * @description Tests the scenario where the payload contains empty or null data.
     */
    @isTest
    static void testUploadWithEmptyData() {
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        
        // Payload with invalid file data
        List<SupervisorLeadUploadController.FilePayload> payload = new List<SupervisorLeadUploadController.FilePayload>();
        SupervisorLeadUploadController.FilePayload emptyFile = new SupervisorLeadUploadController.FilePayload();
        emptyFile.fileName = ''; // Empty name
        payload.add(emptyFile);

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/supervisor/lead/upload/' + testLead.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(payload));

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadUploadController.upload();
        Test.stopTest();

        SupervisorLeadUploadController.UploadResponse result = 
            (SupervisorLeadUploadController.UploadResponse)JSON.deserialize(
                res.responseBody.toString(), 
                SupervisorLeadUploadController.UploadResponse.class
            );

        Assert.isTrue(result.success, 'Success should still be true even if 0 files processed');
        Assert.areEqual(0, result.uploaded, 'Zero files should be uploaded for empty data');
    }

    /**
     * @description Tests the exception handling (e.g., malformed JSON).
     */
    @isTest
    static void testUploadException() {
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/supervisor/lead/upload/' + testLead.Id;
        req.httpMethod = 'POST';
        // Sending invalid JSON to trigger catch block
        req.requestBody = Blob.valueOf(' { "invalid": json '); 

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadUploadController.upload();
        Test.stopTest();

        Assert.areEqual(500, res.statusCode, 'Status code should be 500 on error');
        
        SupervisorLeadUploadController.UploadResponse result = 
            (SupervisorLeadUploadController.UploadResponse)JSON.deserialize(
                res.responseBody.toString(), 
                SupervisorLeadUploadController.UploadResponse.class
            );
        Assert.isFalse(result.success, 'Success flag should be false');
        Assert.areNotEqual(null, result.message, 'Error message should be populated');
    }
}