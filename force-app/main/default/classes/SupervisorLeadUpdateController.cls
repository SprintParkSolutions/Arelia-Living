@RestResource(urlMapping='/supervisor/lead/update/*')
global with sharing class SupervisorLeadUpdateController {

    global class UpdateRequest {
        public String name;
        public String email;
        public String phone;
        public String status;
        public String rating;
        public String siteLocation;
        public String projectDescription;
        public Decimal customerBudget;
        public String typeOfProject;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static void updateLead() {

        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String leadId =
            RestContext.request.requestURI.substringAfterLast('/');

        ResponseWrapper out = new ResponseWrapper();

        try {
            UpdateRequest req =
                (UpdateRequest) JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    UpdateRequest.class
                );

            Lead l = new Lead();
            l.Id = leadId;

            /* =====================================================
               ✅ CORRECT NAME HANDLING (APEX SAFE)
               ===================================================== */
            if (!String.isBlank(req.name)) {

                String trimmedName = req.name.trim();
                List<String> parts = trimmedName.split('\\s+');

                if (parts.size() == 1) {
                    // Only one word → Salesforce requires LastName
                    l.LastName = parts[0];
                } else {
                    // First word → FirstName
                    l.FirstName = parts[0];

                    // Remaining words → LastName
                    String lastName = '';
                    for (Integer i = 1; i < parts.size(); i++) {
                        lastName += parts[i];
                        if (i < parts.size() - 1) {
                            lastName += ' ';
                        }
                    }
                    l.LastName = lastName;
                }
            }

            /* ================= STANDARD FIELDS ================= */
            if (!String.isBlank(req.email)) l.Email = req.email;
            if (!String.isBlank(req.phone)) l.Phone = req.phone;
            if (!String.isBlank(req.status)) l.Status = req.status;
            if (!String.isBlank(req.rating)) l.Rating = req.rating;

            /* ================= CUSTOM FIELDS ================= */
            l.Site_Location__c = req.siteLocation;
            l.Project_Description__c = req.projectDescription;
            l.Customer_Budget__c = req.customerBudget;
            l.Type_Of_Project__c = req.typeOfProject;

            update l;

            out.success = true;
            out.message = 'Lead updated successfully';

        } catch (Exception e) {
            out.success = false;
            out.message = e.getMessage();
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}