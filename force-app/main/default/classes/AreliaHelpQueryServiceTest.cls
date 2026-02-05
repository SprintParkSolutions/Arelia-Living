/**
 * @description Optimized Test class for AreliaHelpQueryService
 * Targets every specific branch of the validation logic to push coverage over 90%.
 */
@isTest
private class AreliaHelpQueryServiceTest {

    @isTest
    static void testSubmitSuccess() {
        AreliaHelpQueryService.HelpRequestDTO dto = new AreliaHelpQueryService.HelpRequestDTO();
        dto.name = 'John Doe';
        dto.email = 'john@example.com';
        dto.message = 'Test message';
        
        setupContext(JSON.serialize(dto));

        Test.startTest();
        AreliaHelpQueryService.HelpResponseDTO res = AreliaHelpQueryService.submit();
        Test.stopTest();

        System.assertEquals(true, res.success, 'Should be true on valid input');
    }

    @isTest
    static void testMissingName() {
        // Test first part of the OR condition
        AreliaHelpQueryService.HelpRequestDTO dto = new AreliaHelpQueryService.HelpRequestDTO();
        dto.name = ''; 
        dto.email = 'test@test.com';
        dto.message = 'test';
        
        setupContext(JSON.serialize(dto));
        AreliaHelpQueryService.HelpResponseDTO res = AreliaHelpQueryService.submit();
        System.assertEquals(false, res.success, 'Should fail for missing name');
    }

    @isTest
    static void testMissingEmail() {
        // Test second part of the OR condition
        AreliaHelpQueryService.HelpRequestDTO dto = new AreliaHelpQueryService.HelpRequestDTO();
        dto.name = 'John';
        dto.email = null; 
        dto.message = 'test';
        
        setupContext(JSON.serialize(dto));
        AreliaHelpQueryService.HelpResponseDTO res = AreliaHelpQueryService.submit();
        System.assertEquals(false, res.success, 'Should fail for missing email');
    }

    @isTest
    static void testMissingMessage() {
        // Test third part of the OR condition
        AreliaHelpQueryService.HelpRequestDTO dto = new AreliaHelpQueryService.HelpRequestDTO();
        dto.name = 'John';
        dto.email = 'test@test.com';
        dto.message = '   '; // Blank whitespace
        
        setupContext(JSON.serialize(dto));
        AreliaHelpQueryService.HelpResponseDTO res = AreliaHelpQueryService.submit();
        System.assertEquals(false, res.success, 'Should fail for missing message');
    }

    @isTest
    static void testJsonException() {
        // Triggers the Catch block via malformed JSON
        setupContext('{"name": "John", "email": "test@test.com" ... malformed}');

        Test.startTest();
        AreliaHelpQueryService.HelpResponseDTO res = AreliaHelpQueryService.submit();
        Test.stopTest();

        System.assertEquals(false, res.success, 'Should catch JSON exception');
        System.assertNotEquals(null, res.errorMessage, 'Should have an error message');
    }

    @isTest
    static void testNullPointerCatch() {
        // Triggers the Catch block via null request body
        RestRequest req = new RestRequest();
        req.requestBody = null; 
        RestContext.request = req;

        Test.startTest();
        AreliaHelpQueryService.HelpResponseDTO res = AreliaHelpQueryService.submit();
        Test.stopTest();

        System.assertEquals(false, res.success, 'Should catch NullPointerException');
    }

    private static void setupContext(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/AreliaHelpQuery/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
    }
}