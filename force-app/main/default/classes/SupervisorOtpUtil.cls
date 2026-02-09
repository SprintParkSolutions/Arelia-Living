public with sharing class SupervisorOtpUtil {

    private static final Integer OTP_EXPIRY_MINUTES = 5;

    // ================= VALIDATE USER =================
    public static Boolean isValidSupervisorEmail(String email) {

        return [
            SELECT COUNT()
            FROM User
            WHERE Email = :email
            AND IsActive = true
        ] > 0;
    }

    // ================= GENERATE OTP =================
    public static String generateOtp() {
        String rand = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        while (rand.length() < 6) rand = '0' + rand;
        return rand.substring(rand.length() - 6);
    }

    // ================= STORE OTP =================
    public static void storeOtp(String email, String otp) {

        // Invalidate old OTPs
        List<Supervisor_OTP__c> oldOtps = [
            SELECT Id
            FROM Supervisor_OTP__c
            WHERE Email__c = :email
            AND Is_Used__c = false
        ];
        for (Supervisor_OTP__c o : oldOtps) {
            o.Is_Used__c = true;
        }
        if (!oldOtps.isEmpty()) update oldOtps;

        // Create new OTP
        insert new Supervisor_OTP__c(
            Email__c = email,
            OTP__c = otp,
            Expiry_Time__c = System.now().addMinutes(OTP_EXPIRY_MINUTES),
            Is_Used__c = false
        );
    }

    // ================= VERIFY OTP =================
    public static Boolean verifyOtp(String email, String enteredOtp) {

        List<Supervisor_OTP__c> records = [
            SELECT Id, Expiry_Time__c, OTP__c
            FROM Supervisor_OTP__c
            WHERE Email__c = :email
            AND OTP__c = :enteredOtp
            AND Is_Used__c = false
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (records.isEmpty()) return false;

        Supervisor_OTP__c otpRec = records[0];

        if (System.now() > otpRec.Expiry_Time__c) {
            otpRec.Is_Used__c = true;
            update otpRec;
            return false;
        }

        otpRec.Is_Used__c = true;
        update otpRec;
        return true;
    }
}