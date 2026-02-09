@RestResource(urlMapping='/mobileSupportCase')
global with sharing class MobileSupportCaseAPI {

    // ✅ RESPONSE WRAPPER
    global class CaseResponse {
        public Boolean success;
        public String caseId;
        public String message;
    }

    @HttpPost
    global static CaseResponse createCase() {

        CaseResponse response = new CaseResponse();

        try {
            RestRequest req = RestContext.request;
            String body = req.requestBody.toString();

            Map<String, Object> data =
                (Map<String, Object>) JSON.deserializeUntyped(body);

            Case c = new Case();
            c.Subject     = (String) data.get('subject');
            c.Description = (String) data.get('description');
            c.Priority    = (String) data.get('priority');
            c.Origin      = 'Mobile App';
            c.ContactId   = (String) data.get('contactId');
            c.Type        = (String) data.get('category');
            c.Status      = 'New';

            insert c;

            response.success = true;
            response.caseId = c.Id;
            response.message = 'Case created successfully';

        } catch (Exception e) {
            response.success = false;
            response.message = e.getMessage();
        }

        return response;
    }
}