@RestResource(urlMapping='/supervisor/leads')
global with sharing class SupervisorLeadController {

    global class LeadDTO {
        public String id;
        public String name;
        public String status;
        public String typeOfProject;
        public Decimal customerBudget;
    }

    global class ResponseWrapper {
        public Boolean success;
        public Integer page;
        public Integer totalPages;
        public Integer totalRecords;
        public List<LeadDTO> data;
        public String message;
    }

    @HttpGet
    global static void getSupervisorLeads() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        Integer page = req.params.get('page') == null ? 1 : Integer.valueOf(req.params.get('page'));
        Integer size = req.params.get('size') == null ? 10 : Integer.valueOf(req.params.get('size'));
        String search = req.params.get('search');

        Integer offsetVal = (page - 1) * size;

        ResponseWrapper wrapper = new ResponseWrapper();
        wrapper.data = new List<LeadDTO>();
        wrapper.page = page;

        try {
            // ✅ Logged-in user email
            String userEmail = [
                SELECT Email FROM User WHERE Id = :UserInfo.getUserId()
            ].Email;

            userEmail = String.escapeSingleQuotes(userEmail);

            // ✅ Base Query
            String baseQuery =
                ' FROM Lead WHERE Supervisor_User__r.Email = \'' + userEmail + '\'';

            // ✅ Search filter
            if (String.isNotBlank(search)) {
                search = '%' + String.escapeSingleQuotes(search) + '%';
                baseQuery +=
                    ' AND (Name LIKE \'' + search + '\'' +
                    ' OR Status LIKE \'' + search + '\'' +
                    ' OR Type_Of_Project__c LIKE \'' + search + '\')';
            }

            // ✅ Count
            wrapper.totalRecords =
                (Integer)Database.countQuery('SELECT COUNT() ' + baseQuery);

            // ✅ Data
            List<Lead> leads = Database.query(
                'SELECT Id, Name, Status, Type_Of_Project__c, Customer_Budget__c ' +
                baseQuery +
                ' ORDER BY CreatedDate DESC' +
                ' LIMIT ' + size +
                ' OFFSET ' + offsetVal
            );

            for (Lead l : leads) {
                LeadDTO dto = new LeadDTO();
                dto.id = l.Id;
                dto.name = l.Name;
                dto.status = l.Status;
                dto.typeOfProject = l.Type_Of_Project__c;
                dto.customerBudget = l.Customer_Budget__c;
                wrapper.data.add(dto);
            }

            wrapper.success = true;
            wrapper.totalPages =
                (Integer)Math.ceil((Decimal)wrapper.totalRecords / size);

        } catch (Exception e) {
            wrapper.success = false;
            wrapper.message = e.getMessage();
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(wrapper));
    }
}