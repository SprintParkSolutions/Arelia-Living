@RestResource(urlMapping='/mobile/payment-terms-auth')
global with sharing class PaymentTermAuthRest {

    @HttpPost
    global static List<PaymentTermDTO> getTerms() {

        RestRequest req = RestContext.request;

        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(
                req.requestBody.toString()
            );

        String projectName = (String) payload.get('projectName');

        System.debug('🔥 PROJECT NAME RECEIVED: ' + projectName);

        return PaymentTermController.getPaymentTermsByProjectName(projectName);
    }
}