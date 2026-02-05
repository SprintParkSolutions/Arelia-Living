/**
 * @description Test class for SupervisorCreateLeadController
 * Uses dynamic schema checks to ensure the correct ID type is passed to lookups.
 */
@isTest
private class SupervisorCreateLeadControllerTest {

    @isTest
    static void testCreateLeadSuccess() {
        // 1. DYNAMIC FIX: Identify the correct object type for Interior_Category__c
        // This ensures we don't get a FIELD_INTEGRITY_EXCEPTION
        Schema.DescribeFieldResult fieldResult = Lead.Interior_Category__c.getDescribe();
        Schema.sObjectType targetType = fieldResult.getReferenceTo()[0];
        
        // Create a generic record of the expected type
        SObject genericCategory = targetType.newSObject();
        
        // Set a Name field if it's not an AutoNumber
        if (targetType.getDescribe().fields.getMap().containsKey('Name')) {
            genericCategory.put('Name', 'Test Category');
        }
        insert genericCategory;

        // 2. Prepare Request Body
        SupervisorCreateLeadController.CreateLeadRequest req = new SupervisorCreateLeadController.CreateLeadRequest();
        req.fullName = 'John Winston Smith';
        req.salutation = 'Mr.';
        req.email = 'john.smith@example.com';
        req.phone = '1234567890';
        req.leadStatus = 'Open - Not Contacted';
        req.projectType = 'Residential';
        req.quotationType = 'Automation';
        req.siteLocation = 'New York';
        req.projectDescription = 'Testing REST API';
        req.typeOfProject = 'Home';
        
        // Pass the ID of the dynamically created record
        req.interiorCategory = genericCategory.Id; 
        req.estimatedBudget = 50000;

        // 3. Set up RestContext
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/services/apexrest/supervisor/lead/create';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(req));
        
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        SupervisorCreateLeadController.createLead();
        Test.stopTest();

        // 4. Verify Response
        String responseJson = RestContext.response.responseBody.toString();
        SupervisorCreateLeadController.CreateLeadResponse resWrapper = 
            (SupervisorCreateLeadController.CreateLeadResponse) JSON.deserialize(
                responseJson, 
                SupervisorCreateLeadController.CreateLeadResponse.class
            );

        Assert.isTrue(resWrapper.success, 'Lead creation failed. Message: ' + resWrapper.message);
        Assert.isNotNull(resWrapper.leadId, 'Lead ID should not be null');

        // 5. Verify Name Splitting Logic
        Lead insertedLead = [SELECT FirstName, LastName FROM Lead WHERE Id = :resWrapper.leadId LIMIT 1];
        Assert.areEqual('John', insertedLead.FirstName, 'First name should be first part');
        Assert.areEqual('Winston Smith', insertedLead.LastName, 'Last name should be remaining parts');
    }

    @isTest
    static void testCreateLeadBlankName() {
        SupervisorCreateLeadController.CreateLeadRequest req = new SupervisorCreateLeadController.CreateLeadRequest();
        req.fullName = ''; 

        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf(JSON.serialize(req));
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        SupervisorCreateLeadController.createLead();
        Test.stopTest();

        Lead insertedLead = [SELECT FirstName, LastName FROM Lead LIMIT 1];
        // 'Mobile Lead' splitting check
        Assert.areEqual('Mobile', insertedLead.FirstName);
        Assert.areEqual('Lead', insertedLead.LastName);
    }

    @isTest
    static void testCreateLeadFailure() {
        RestRequest request = new RestRequest();
        request.requestBody = Blob.valueOf('{"invalid_json":}'); 
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        SupervisorCreateLeadController.createLead();
        Test.stopTest();

        Assert.areEqual(500, RestContext.response.statusCode);
    }
}