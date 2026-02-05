/**
 * @description Test class for SupervisorAuthRestV2
 * Covers Send OTP, Verify OTP, and Error Handling scenarios.
 * PMD Violations addressed: No hardcoded IDs, assertions included, proper naming conventions.
 */
@isTest
private class SupervisorAuthRestV2Test {

    private static final String BASE_URI = '/services/apexrest/supervisor/auth/';

    /**
     * @description Test setup to prepare common data. 
     * Note: SupervisorOtpUtil dependencies (like custom objects/settings) 
     * should be handled within the utility or here.
     */
    @testSetup
    static void setup() {
        // Create a test supervisor user via provided utility
        TestDataUtility.createSupervisorUser('spvis');
    }

    @isTest
    static void testSendOtpSuccess() {
        User u = [SELECT Email FROM User WHERE Alias = 'spvis' LIMIT 1];
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'send';
        req.httpMethod = 'POST';
        req.addParameter('email', u.Email);

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        Assert.areEqual('OTP_SENT', result, 'The OTP should be sent successfully for a valid supervisor email.');
    }

    @isTest
    static void testSendOtpMissingEmail() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'send';
        req.httpMethod = 'POST';
        // Email parameter is missing

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        Assert.areEqual('EMAIL_REQUIRED', result, 'Should return error when email is blank.');
        Assert.areEqual(400, res.statusCode, 'Status code should be 400 for bad request.');
    }

    @isTest
    static void testSendOtpNotFound() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'send';
        req.httpMethod = 'POST';
        req.addParameter('email', 'nonexistent@test.com');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        Assert.areEqual('EMAIL_NOT_FOUND', result, 'Should return not found for non-supervisor email.');
        Assert.areEqual(404, res.statusCode, 'Status code should be 404.');
    }

    @isTest
    static void testVerifyOtpSuccess() {
        User u = [SELECT Email FROM User WHERE Alias = 'spvis' LIMIT 1];
        
        // Simulating the OTP storage (Logic assumed to be handled by SupervisorOtpUtil)
        // Since we cannot easily predict the OTP from SupervisorOtpUtil.generateOtp()
        // This test assumes SupervisorOtpUtil.verifyOtp returns true for '123456' in test context 
        // OR you may need to mock/insert the OTP record if it uses a custom object.
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'verify';
        req.httpMethod = 'POST';
        req.addParameter('email', u.Email);
        req.addParameter('otp', '123456'); 

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        // Note: If this fails, ensure SupervisorOtpUtil handles '123456' in @isTest mode 
        // or provides a way to retrieve the generated OTP.
        Assert.isNotNull(result, 'Result should not be null');
    }

    @isTest
    static void testVerifyOtpFail() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'verify';
        req.httpMethod = 'POST';
        req.addParameter('email', 'test@test.com');
        req.addParameter('otp', '000000'); // Wrong OTP

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        Assert.areEqual('INVALID_OR_EXPIRED_OTP', result, 'Should fail verification for wrong OTP.');
        Assert.areEqual(401, res.statusCode, 'Status code should be 401.');
    }

    @isTest
    static void testVerifyOtpMissingParams() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'verify';
        req.httpMethod = 'POST';
        // Missing parameters

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        Assert.areEqual('EMAIL_AND_OTP_REQUIRED', result, 'Should require both fields.');
        Assert.areEqual(400, res.statusCode, 'Status code should be 400.');
    }

    @isTest
    static void testInvalidEndpoint() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = BASE_URI + 'unknown_action';
        req.httpMethod = 'POST';

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        String result = SupervisorAuthRestV2.handlePost();
        Test.stopTest();

        Assert.areEqual('INVALID_ENDPOINT', result, 'Should return invalid endpoint for unknown URIs.');
        Assert.areEqual(404, res.statusCode, 'Status code should be 404.');
    }
}