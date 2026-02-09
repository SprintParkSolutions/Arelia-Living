/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-09-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class SupervisorOtpUtilTest {

    /**
     * @description Sets up the test data for the test methods.
     * Uses the provided TestDataUtility where possible.
     */
    @testSetup
    static void setup() {
        // Create a standard supervisor user
        TestDataUtility.createSupervisorUser('spvsor');
    }

    /**
     * @description Tests the validation of a supervisor email.
     */
    @isTest
    static void testIsValidSupervisorEmail() {
        User testUser = [SELECT Email FROM User WHERE Alias = 'spvsor' LIMIT 1];
        
        Test.startTest();
        Boolean isValid = SupervisorOtpUtil.isValidSupervisorEmail(testUser.Email);
        Boolean isInvalid = SupervisorOtpUtil.isValidSupervisorEmail('nonexistent@test.com');
        Test.stopTest();

        Assert.isTrue(isValid, 'The existing user email should be valid.');
        Assert.isFalse(isInvalid, 'A non-existent email should be invalid.');
    }

    /**
     * @description Tests the OTP generation logic.
     */
    @isTest
    static void testGenerateOtp() {
        Test.startTest();
        String otp1 = SupervisorOtpUtil.generateOtp();
        String otp2 = SupervisorOtpUtil.generateOtp();
        Test.stopTest();

        Assert.areEqual(6, otp1.length(), 'OTP length must be 6 digits.');
        Assert.isTrue(otp1.isNumeric(), 'OTP should only contain numeric characters.');
        // While theoretically possible to be the same, Crypto.getRandomInteger makes it highly unlikely
        Assert.areNotEqual(otp1, otp2, 'Consecutive OTPs should generally be unique.');
    }

    /**
     * @description Tests storing an OTP and ensures old ones are invalidated.
     */
    @isTest
    static void testStoreOtp() {
        String testEmail = 'supervisor@test.com';
        String firstOtp = '111111';
        String secondOtp = '222222';

        Test.startTest();
        // Insert first OTP
        SupervisorOtpUtil.storeOtp(testEmail, firstOtp);
        
        // Insert second OTP - should invalidate the first one
        SupervisorOtpUtil.storeOtp(testEmail, secondOtp);
        Test.stopTest();

        List<Supervisor_OTP__c> otps = [
            SELECT OTP__c, Is_Used__c 
            FROM Supervisor_OTP__c 
            WHERE Email__c = :testEmail 
            ORDER BY CreatedDate ASC
        ];

        Assert.areEqual(2, otps.size(), 'Two OTP records should exist.');
        Assert.isTrue(otps[0].Is_Used__c, 'The first OTP should have been marked as used (invalidated).');
        Assert.isFalse(otps[1].Is_Used__c, 'The latest OTP should be active (not used).');
        Assert.areEqual(secondOtp, otps[1].OTP__c, 'The latest OTP value should match.');
    }

    /**
     * @description Tests successful OTP verification.
     */
    @isTest
    static void testVerifyOtpSuccess() {
        String testEmail = 'verify@test.com';
        String otpCode = '123456';
        SupervisorOtpUtil.storeOtp(testEmail, otpCode);

        Test.startTest();
        Boolean result = SupervisorOtpUtil.verifyOtp(testEmail, otpCode);
        Test.stopTest();

        Assert.isTrue(result, 'OTP verification should succeed for valid code and email.');
        
        Supervisor_OTP__c updatedRecord = [SELECT Is_Used__c FROM Supervisor_OTP__c WHERE Email__c = :testEmail LIMIT 1];
        Assert.isTrue(updatedRecord.Is_Used__c, 'OTP record should be marked as used after verification.');
    }

    /**
     * @description Tests OTP verification failure due to incorrect code.
     */
    @isTest
    static void testVerifyOtpWrongCode() {
        String testEmail = 'wrong@test.com';
        SupervisorOtpUtil.storeOtp(testEmail, '111111');

        Test.startTest();
        Boolean result = SupervisorOtpUtil.verifyOtp(testEmail, '000000');
        Test.stopTest();

        Assert.isFalse(result, 'OTP verification should fail for incorrect code.');
    }

    /**
     * @description Tests OTP verification failure due to expiration.
     */
    @isTest
    static void testVerifyOtpExpired() {
        String testEmail = 'expired@test.com';
        String otpCode = '999999';
        
        // Manually create an expired record as we cannot easily mock System.now() inside the utility
        Supervisor_OTP__c expiredOtp = new Supervisor_OTP__c(
            Email__c = testEmail,
            OTP__c = otpCode,
            Expiry_Time__c = System.now().addMinutes(-10), // Expired 10 mins ago
            Is_Used__c = false
        );
        insert expiredOtp;

        Test.startTest();
        Boolean result = SupervisorOtpUtil.verifyOtp(testEmail, otpCode);
        Test.stopTest();

        Assert.isFalse(result, 'OTP verification should fail if the code is expired.');
        
        Supervisor_OTP__c updatedRecord = [SELECT Is_Used__c FROM Supervisor_OTP__c WHERE Id = :expiredOtp.Id];
        Assert.isTrue(updatedRecord.Is_Used__c, 'Expired OTP record should be marked as used (invalidated) after check.');
    }

    /**
     * @description Tests behavior when no OTP record exists for the email.
     */
    @isTest
    static void testVerifyOtpNoRecord() {
        Test.startTest();
        Boolean result = SupervisorOtpUtil.verifyOtp('nonexistent@test.com', '123456');
        Test.stopTest();

        Assert.isFalse(result, 'Verification should fail if no record is found.');
    }
}