/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-04-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@RestResource(urlMapping='/supervisor/lead/*')
global with sharing class SupervisorLeadDetailsController {

    global class RowDTO {
        public String label;
        public String value;
    }

    global class SectionDTO {
        public String title;
        public List<RowDTO> rows;
    }

    global class ResponseWrapper {
        public Boolean success;
        public List<SectionDTO> sections;
        public String message;
    }

    @HttpGet
    global static void getLeadDetails() {

        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String leadId =
            RestContext.request.requestURI.substringAfterLast('/');

        ResponseWrapper out = new ResponseWrapper();
        out.sections = new List<SectionDTO>();

        try {
            Lead l = [
                SELECT Name, Email, Phone, Status, Rating,
                       Project_Request_Quotation_Type__c,
                       Site_Location__c,
                       Project_Description__c,
                       Type_Of_Project__c,
                       Interior_Category__c,
                       Estimated_Budget__c,
                       Customer_Budget__c,
                       Site_Visit_Status__c,
                       Site_Visit_Manager_Approval__c,
                       Supervisor_User__r.Name,
                       Supervisor_User__r.Email,
                       Supervisor_User__r.Phone
                FROM Lead WHERE Id = :leadId
            ];

            /* ---------------- LEAD INFO ---------------- */
            SectionDTO leadInfo = new SectionDTO();
            leadInfo.title = 'Lead Information';
            leadInfo.rows = new List<RowDTO>{
                row('Name', l.Name),
                row('Email', l.Email),
                row('Phone', l.Phone),
                row('Lead Status', l.Status),
                row('Rating', l.Rating)
            };
            out.sections.add(leadInfo);

            /* ---------------- PROJECT INFO ---------------- */
            SectionDTO project = new SectionDTO();
            project.title = 'Project Information';
            project.rows = new List<RowDTO>{
                row('Project Request Quotation Type',
                    l.Project_Request_Quotation_Type__c),
                row('Site Location', l.Site_Location__c),
                row('Project Description', l.Project_Description__c)
            };
            out.sections.add(project);

            /* ---------------- MANUAL PROJECT ---------------- */
            SectionDTO manual = new SectionDTO();
            manual.title = 'Manual Project Request Information';
            manual.rows = new List<RowDTO>{
                row('Type Of Project', l.Type_Of_Project__c),
                row('Interior Category', l.Interior_Category__c),
                row('Estimated Budget',
                    l.Estimated_Budget__c != null
                        ? String.valueOf(l.Estimated_Budget__c) : null),
                row('Customer Budget',
                    l.Customer_Budget__c != null
                        ? String.valueOf(l.Customer_Budget__c) : null)
            };
            out.sections.add(manual);

            /* ---------------- SITE VISIT ---------------- */
            SectionDTO site = new SectionDTO();
            site.title = 'Site Visit Information';
            site.rows = new List<RowDTO>{
                row('Site Visit Status', l.Site_Visit_Status__c),
                row('Site Visit Manager Approval',
                    String.valueOf(l.Site_Visit_Manager_Approval__c))
            };
            out.sections.add(site);

            /* ---------------- SUPERVISOR ---------------- */
            if (l.Supervisor_User__r != null) {
                SectionDTO sup = new SectionDTO();
                sup.title = 'Supervisor Information';
                sup.rows = new List<RowDTO>{
                    row('Supervisor Name',
                        l.Supervisor_User__r.Name),
                    row('Supervisor Email',
                        l.Supervisor_User__r.Email),
                    row('Supervisor Phone',
                        l.Supervisor_User__r.Phone)
                };
                out.sections.add(sup);
            }

            out.success = true;
            res.statusCode = 200;

        } catch (Exception e) {
            out.success = false;
            out.message = e.getMessage();
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }

    private static RowDTO row(String label, String value) {
        RowDTO r = new RowDTO();
        r.label = label;
        r.value = value != null ? value : '-';
        return r;
    }
}