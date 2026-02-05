@RestResource(urlMapping='/supervisor/auth/*')
global without sharing class SupervisorAuthRestV2 {

    @HttpPost
    global static String handlePost() {

        RestRequest req = RestContext.request;
        String uri = (req.requestURI == null) ? '' : req.requestURI.toLowerCase();

        String email = req.params.get('email');
        String otp   = req.params.get('otp');

        if (uri.endsWith('/send')) {
            return sendOtp(email);
        }
        else if (uri.endsWith('/verify')) {
            return verifyOtp(email, otp);
        }
        else {
            RestContext.response.statusCode = 404;
            return 'INVALID_ENDPOINT';
        }
    }

    private static String sendOtp(String email) {

        if (String.isBlank(email)) {
            RestContext.response.statusCode = 400;
            return 'EMAIL_REQUIRED';
        }

        if (!SupervisorOtpUtil.isValidSupervisorEmail(email)) {
            RestContext.response.statusCode = 404;
            return 'EMAIL_NOT_FOUND';
        }

        String otpCode = SupervisorOtpUtil.generateOtp();
        SupervisorOtpUtil.storeOtp(email, otpCode);
        SupervisorEmailService.sendOtp(email, otpCode);

        return 'OTP_SENT';
    }

    private static String verifyOtp(String email, String otp) {

        if (String.isBlank(email) || String.isBlank(otp)) {
            RestContext.response.statusCode = 400;
            return 'EMAIL_AND_OTP_REQUIRED';
        }

        if (!SupervisorOtpUtil.verifyOtp(email, otp)) {
            RestContext.response.statusCode = 401;
            return 'INVALID_OR_EXPIRED_OTP';
        }

        return 'OTP_VERIFIED';
    }
}