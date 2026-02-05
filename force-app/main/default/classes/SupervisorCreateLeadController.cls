@RestResource(urlMapping='/supervisor/lead/create')
global with sharing class SupervisorCreateLeadController {

    global class CreateLeadRequest {
        public String fullName;
        public String salutation;
        public String email;
        public String phone;
        public String leadStatus;

        public String projectType;
        public String quotationType;
        public String siteLocation;
        public String projectDescription;

        public String typeOfProject;
        public String interiorCategory;
        public Decimal estimatedBudget;
    }

    global class CreateLeadResponse {
        public Boolean success;
        public String leadId;
        public String message;
    }

    @HttpPost
    global static void createLead() {

        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        CreateLeadResponse out = new CreateLeadResponse();

        try {
            CreateLeadRequest reqBody = (CreateLeadRequest)
                JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    CreateLeadRequest.class
                );

            Lead l = new Lead();

            // ✅ SAFE name split (Apex-compatible)
            String name = String.isBlank(reqBody.fullName)
                ? 'Mobile Lead'
                : reqBody.fullName.trim();

            List<String> parts = name.split('\\s+');

            if (parts.size() == 1) {
                l.LastName = parts[0];
            } else {
                l.FirstName = parts[0];

                String lastName = '';
                for (Integer i = 1; i < parts.size(); i++) {
                    lastName += parts[i];
                    if (i < parts.size() - 1) {
                        lastName += ' ';
                    }
                }
                l.LastName = lastName;
            }

            // 🔹 Basic fields
            l.Salutation = reqBody.salutation;
            l.Email = reqBody.email;
            l.Phone = reqBody.phone;
            l.Status = String.isBlank(reqBody.leadStatus) ? 'New' : reqBody.leadStatus;

            // 🔹 Project fields
            l.Project_Type__c = reqBody.projectType;
            l.Project_Request_Quotation_Type__c = reqBody.quotationType;
            l.Site_Location__c = reqBody.siteLocation;
            l.Project_Description__c = reqBody.projectDescription;

            // 🔹 Manual Project Request
            l.Type_Of_Project__c = reqBody.typeOfProject;
            l.Interior_Category__c = reqBody.interiorCategory;
            l.Estimated_Budget__c = reqBody.estimatedBudget;

            insert l;

            out.success = true;
            out.leadId = l.Id;

        } catch (Exception e) {
            out.success = false;
            out.message = e.getMessage();
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}