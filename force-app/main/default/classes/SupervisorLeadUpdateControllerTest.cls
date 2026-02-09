/**
 * @description Test class for SupervisorLeadUpdateController
 * High coverage and PMD compliant.
 */
@isTest
private class SupervisorLeadUpdateControllerTest {

    @isTest
    static void testUpdateLeadSuccessMultiWord() {
        // Setup data using provided utility
        Lead testLead = TestDataUtility.createLead('OriginalName');
        
        // Prepare request body
        SupervisorLeadUpdateController.UpdateRequest req = new SupervisorLeadUpdateController.UpdateRequest();
        req.name = 'John Doe Smith';
        req.email = 'john.doe@test.com';
        req.phone = '1234567890';
        req.status = 'Working';
        req.rating = 'Hot';
        req.siteLocation = 'New York';
        req.projectDescription = 'Kitchen Remodel';
        req.customerBudget = 50000;
        req.typeOfProject = 'Home';

        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();

        request.requestURI = '/services/apexrest/supervisor/lead/update/' + testLead.Id;
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(req));
        
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        SupervisorLeadUpdateController.updateLead();
        Test.stopTest();

        // Verify Lead Updates
        Lead updatedLead = [SELECT FirstName, LastName, Email, Site_Location__c FROM Lead WHERE Id = :testLead.Id];
        Assert.areEqual('John', updatedLead.FirstName, 'First name should be the first part of name');
        Assert.areEqual('Doe Smith', updatedLead.LastName, 'Last name should contain remaining parts');
        Assert.areEqual('john.doe@test.com', updatedLead.Email, 'Email should be updated');
        Assert.areEqual('New York', updatedLead.Site_Location__c, 'Custom field site location should be updated');

        // Verify Response
        SupervisorLeadUpdateController.ResponseWrapper resBody = 
            (SupervisorLeadUpdateController.ResponseWrapper) JSON.deserialize(
                response.responseBody.toString(), 
                SupervisorLeadUpdateController.ResponseWrapper.class
            );
        Assert.isTrue(resBody.success, 'Response success should be true');
    }

    @isTest
    static void testUpdateLeadSuccessSingleWord() {
        Lead testLead = TestDataUtility.createLead('Initial');
        
        SupervisorLeadUpdateController.UpdateRequest req = new SupervisorLeadUpdateController.UpdateRequest();
        req.name = 'SingleName';

        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();

        request.requestURI = '/services/apexrest/supervisor/lead/update/' + testLead.Id;
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(req));
        
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        SupervisorLeadUpdateController.updateLead();
        Test.stopTest();

        Lead updatedLead = [SELECT LastName FROM Lead WHERE Id = :testLead.Id];
        Assert.areEqual('SingleName', updatedLead.LastName, 'LastName should be updated even if single word provided');
    }

    @isTest
    static void testUpdateLeadInvalidId() {
        // Provide a valid format but non-existent Lead ID to trigger exception
        String fakeId = '00Q000000000000AAA';
        
        SupervisorLeadUpdateController.UpdateRequest req = new SupervisorLeadUpdateController.UpdateRequest();
        req.email = 'error@test.com';

        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();

        request.requestURI = '/services/apexrest/supervisor/lead/update/' + fakeId;
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(req));
        
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        SupervisorLeadUpdateController.updateLead();
        Test.stopTest();

        // Verify Error Response
        Assert.areEqual(500, response.statusCode, 'Status code should be 500 on error');
        SupervisorLeadUpdateController.ResponseWrapper resBody = 
            (SupervisorLeadUpdateController.ResponseWrapper) JSON.deserialize(
                response.responseBody.toString(), 
                SupervisorLeadUpdateController.ResponseWrapper.class
            );
        Assert.isFalse(resBody.success, 'Response success should be false');
        Assert.isNotNull(resBody.message, 'Error message should be populated');
    }
}