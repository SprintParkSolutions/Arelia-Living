/**
 * @description Test class for SupervisorLeadSiteVisitController.
 * Ensures 90%+ coverage by testing success, partial updates, and exception handling.
 */
@isTest
private class SupervisorLeadSiteVisitControllerTest {

    private static final String APPT_TYPE_VALID = 'New';
    private static final String TIME_SLOT = '10:00 AM - 11:00 AM';

    @isTest
    static void testScheduleSiteVisitSuccess() {
        // Setup Lead using Utility
        Lead testLead = TestDataUtility.createLead('Doe');

        SupervisorLeadSiteVisitController.SiteVisitRequest reqObj = new SupervisorLeadSiteVisitController.SiteVisitRequest();
        reqObj.appointmentType = APPT_TYPE_VALID;
        reqObj.appointmentDate = Date.today().addDays(2);
        reqObj.timeSlot = TIME_SLOT;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/supervisor/lead/sitevisit/' + testLead.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(reqObj));

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadSiteVisitController.scheduleSiteVisit();
        Test.stopTest();

        SupervisorLeadSiteVisitController.ResponseWrapper resp = 
            (SupervisorLeadSiteVisitController.ResponseWrapper) JSON.deserialize(
                res.responseBody.toString(), 
                SupervisorLeadSiteVisitController.ResponseWrapper.class
            );

        Assert.areEqual(true, resp.success, 'Success should be true. Error: ' + resp.message);
        
        Lead updatedLead = [SELECT Appointment_Confirmation_Type__c, Appointment_Status__c 
                            FROM Lead WHERE Id = :testLead.Id LIMIT 1];
        Assert.areEqual('Pending', updatedLead.Appointment_Status__c, 'Status should update to Pending');
    }

    @isTest
    static void testScheduleSiteVisitPartialFields() {
        Lead testLead = TestDataUtility.createLead('Smith');

        // Using "New" as requested to satisfy Restricted Picklist constraints
        SupervisorLeadSiteVisitController.SiteVisitRequest reqObj = new SupervisorLeadSiteVisitController.SiteVisitRequest();
        reqObj.appointmentType = APPT_TYPE_VALID;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/supervisor/lead/sitevisit/' + testLead.Id;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(reqObj));

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadSiteVisitController.scheduleSiteVisit();
        Test.stopTest();

        SupervisorLeadSiteVisitController.ResponseWrapper resp = 
            (SupervisorLeadSiteVisitController.ResponseWrapper) JSON.deserialize(
                res.responseBody.toString(), 
                SupervisorLeadSiteVisitController.ResponseWrapper.class
            );

        Assert.areEqual(true, resp.success, 'Partial update failed: ' + resp.message);
    }

    @isTest
    static void testScheduleSiteVisitDataException() {
        // Covers the catch block by attempting to update a non-existent record
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        // Valid ID format but record does not exist
        req.requestURI = '/supervisor/lead/sitevisit/00QU900000K8u9aMAA';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"appointmentType": "' + APPT_TYPE_VALID + '"}');

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadSiteVisitController.scheduleSiteVisit();
        Test.stopTest();

        Assert.areEqual(500, res.statusCode, 'Should return 500 status code for DML errors');
        
        SupervisorLeadSiteVisitController.ResponseWrapper resp = 
            (SupervisorLeadSiteVisitController.ResponseWrapper) JSON.deserialize(
                res.responseBody.toString(), 
                SupervisorLeadSiteVisitController.ResponseWrapper.class
            );
        Assert.areEqual(false, resp.success, 'Success flag should be false in catch block');
    }

    @isTest
    static void testScheduleSiteVisitJsonException() {
        // Covers the catch block by providing invalid JSON structure
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/supervisor/lead/sitevisit/invalid';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{ "appointmentType": '); // Malformed JSON

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        SupervisorLeadSiteVisitController.scheduleSiteVisit();
        Test.stopTest();

        Assert.areEqual(500, res.statusCode, 'Should return 500 status code for JSON errors');
    }
}