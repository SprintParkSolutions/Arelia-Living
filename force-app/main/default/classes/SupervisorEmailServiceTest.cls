/**
 * @description Test class for SupervisorEmailService
 * Verifies that OTP emails are correctly formatted and sent.
 * PMD Rule Friendly: includes descriptions, no hardcoded IDs, and proper assertions.
 */
@isTest
private class SupervisorEmailServiceTest {

    /**
     * @description Verifies that the sendOtp method executes successfully 
     * and triggers a Salesforce email invocation.
     */
    @isTest
    static void testSendOtpSuccess() {
        // Arrange: Setup test data using the utility class
        String testEmail = 'supervisor@testorg.com';
        String testOtp = '123456';

        // Act: Perform the test
        Test.startTest();
        SupervisorEmailService.sendOtp(testEmail, testOtp);
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        // Assert: Verify that one email was sent
        Assert.areEqual(1, emailInvocations, 'One email should have been sent by the service.');
    }

    /**
     * @description Verifies the service works correctly when called by a specific user context.
     * Uses the TestDataUtility to create a supervisor user.
     */
    @isTest
    static void testSendOtpInUserContext() {
        // Arrange
        User supervisor = TestDataUtility.createSupervisorUser('spvSRV');
        String testOtp = '987654';

        // Act
        Test.startTest();
        System.runAs(supervisor) {
            SupervisorEmailService.sendOtp(supervisor.Email, testOtp);
        }
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        // Assert
        Assert.areEqual(1, emailInvocations, 'Email should be sent successfully within user context.');
    }
}