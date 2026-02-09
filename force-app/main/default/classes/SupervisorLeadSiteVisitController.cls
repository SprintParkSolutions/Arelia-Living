@RestResource(urlMapping='/supervisor/lead/sitevisit/*')
global with sharing class SupervisorLeadSiteVisitController {

    global class SiteVisitRequest {
        public String appointmentType;
        public Date appointmentDate;
        public String timeSlot;
    }

    global class ResponseWrapper {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static void scheduleSiteVisit() {

        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String leadId =
            RestContext.request.requestURI.substringAfterLast('/');

        ResponseWrapper out = new ResponseWrapper();

        try {
            SiteVisitRequest req =
                (SiteVisitRequest) JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    SiteVisitRequest.class
                );

            Lead l = new Lead();
            l.Id = leadId;

            /* =====================================================
               ✅ SAFE FIELD UPDATE (DESCRIBE-BASED)
               ===================================================== */

            Map<String, Schema.SObjectField> fields =
                Lead.SObjectType.getDescribe().fields.getMap();

            if (fields.containsKey('Appointment_Confirmation_Type__c')
                && req.appointmentType != null) {

                l.put('Appointment_Confirmation_Type__c', req.appointmentType);
            }

            if (fields.containsKey('Appointment_Confirmed_Date__c')
                && req.appointmentDate != null) {

                l.put('Appointment_Confirmed_Date__c', req.appointmentDate);
            }

            if (fields.containsKey('Appointment_Confirmed_Time_Slot__c')
                && req.timeSlot != null) {

                l.put('Appointment_Confirmed_Time_Slot__c', req.timeSlot);
            }

            if (fields.containsKey('Appointment_Status__c')) {
                l.put('Appointment_Status__c', 'Pending');
            }

            update l;

            out.success = true;
            out.message = 'Site visit scheduled successfully';

        } catch (Exception e) {
            out.success = false;
            out.message = e.getMessage();
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}