@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation')
private class InteriorAutoProjectRequestServiceTest {

    /* ------------------------------------------
       Helper to fetch a valid picklist value
       ------------------------------------------ */
    private static String getFirstPicklistValue(Schema.SObjectField fieldRef) {
        Schema.DescribeFieldResult d = fieldRef.getDescribe();
        List<Schema.PicklistEntry> entries = d.getPicklistValues();
        return entries.isEmpty() ? null : entries[0].getValue();
    }

    /* ------------------------------------------
       Test Setup
       ------------------------------------------ */
    @TestSetup
    static void setupData() {

        Lead ld = new Lead(
            FirstName = 'Test',
            LastName  = 'AutoRequest',
            Company   = 'Arelia Test Co',
            Status    = 'Open - Not Contacted',
            Email     = 'test@example.com'
        );
        insert ld;

        Interior_Room__c room = new Interior_Room__c(Name = 'Living Room');
        insert room;

        Interior_Design__c design = new Interior_Design__c(Name = 'Luxury Design');
        insert design;

        insert new Interior_Request_Room__c(
            Lead__c = ld.Id,
            Interior_Room__c = room.Id,
            Quantity__c = 2
        );

        insert new Interior_Request_Room_Design__c(
            Lead__c = ld.Id,
            Interior_Room__c = room.Id,
            Interior_Design__c = design.Id,
            Quantity__c = 1,
            Design_Amount__c = 150000
        );
    }

    /* ------------------------------------------
       Test: saveRequest Happy Path
       ------------------------------------------ */
    @IsTest
    static void testSaveRequestHappyPath() {

        Lead ld = [SELECT Id FROM Lead LIMIT 1];
        Interior_Room__c room = [SELECT Id FROM Interior_Room__c LIMIT 1];
        Interior_Design__c design = [SELECT Id FROM Interior_Design__c LIMIT 1];

        String quotationTypeVal =
            getFirstPicklistValue(Lead.Project_Request_Quotation_Type__c);

        List<Object> rooms = new List<Object>{
            new Map<String, Object>{
                'roomId' => room.Id,
                'quantity' => 3
            }
        };

        List<Object> designs = new List<Object>{
            new Map<String, Object>{
                'roomId' => room.Id,
                'designId' => design.Id,
                'quantity' => 2,
                'lineAmount' => 250000
            }
        };

        Map<String, Object> req = new Map<String, Object>{
            'leadId' => ld.Id,
            'firstName' => 'UpdatedFirst',
            'lastName' => 'UpdatedLast',
            'email' => 'updated@example.com',
            'phone' => '9999999999',
            'company' => 'Updated Company',
            'address' => 'New Site Address',
            'siteSpace' => '3 BHK, 1400 Sqft',
            'description' => 'Automation test',
            'projectTypeId' => null,
            'categoryId' => null,
            'planLevel' => 'Premium',
            'quotationType' => quotationTypeVal,
            'totalBudget' => 350000,
            'rooms' => rooms,
            'selectedRoomDesigns' => designs
        };

        Test.startTest();
        Id leadId = InteriorAutoProjectRequestService.saveRequest(req);
        Test.stopTest();

        Lead updated = [
            SELECT FirstName, LastName, Email, Phone,
                   Site_Location__c, Site_Space__c,
                   Estimated_Budget__c, Plan_Level__c,
                   Project_Request_Quotation_Type__c,
                   Project_Request_Submitted__c
            FROM Lead WHERE Id = :leadId
        ];

        System.assertEquals('UpdatedFirst', updated.FirstName, 'First name mismatch');
        System.assertEquals('UpdatedLast', updated.LastName, 'Last name mismatch');
        System.assertEquals('updated@example.com', updated.Email, 'Email mismatch');
        System.assertEquals('9999999999', updated.Phone, 'Phone mismatch');
        System.assertEquals('New Site Address', updated.Site_Location__c, 'Address mismatch');
        System.assertEquals('3 BHK, 1400 Sqft', updated.Site_Space__c, 'Site space mismatch');
        System.assertEquals(350000, updated.Estimated_Budget__c, 'Budget mismatch');
        System.assertEquals(quotationTypeVal, updated.Project_Request_Quotation_Type__c, 'Picklist mismatch');
        System.assertEquals(true, updated.Project_Request_Submitted__c, 'Submission flag mismatch');

        List<Interior_Request_Room__c> createdRooms = [
            SELECT Quantity__c FROM Interior_Request_Room__c WHERE Lead__c = :leadId
        ];
        System.assertEquals(1, createdRooms.size(), 'Room record count mismatch');
        System.assertEquals(3, createdRooms[0].Quantity__c, 'Room quantity mismatch');

        List<Interior_Request_Room_Design__c> createdDesigns = [
            SELECT Quantity__c, Design_Amount__c
            FROM Interior_Request_Room_Design__c WHERE Lead__c = :leadId
        ];
        System.assertEquals(1, createdDesigns.size(), 'Design record count mismatch');
        System.assertEquals(2, createdDesigns[0].Quantity__c, 'Design qty mismatch');
        System.assertEquals(250000, createdDesigns[0].Design_Amount__c, 'Design amount mismatch');
    }

    /* ------------------------------------------
       Test: Prevent second submission
       ------------------------------------------ */
    @IsTest
    static void testSaveRequestPreventSecondSubmission() {

        Lead ld = [SELECT Id FROM Lead LIMIT 1];
        ld.Project_Request_Submitted__c = true;
        update ld;

        String quotationTypeVal =
            getFirstPicklistValue(Lead.Project_Request_Quotation_Type__c);

        Map<String, Object> req = new Map<String, Object>{
            'leadId' => ld.Id,
            'firstName' => 'A',
            'lastName' => 'B',
            'email' => 'a@b.com',
            'phone' => '123',
            'company' => 'C',
            'address' => 'D',
            'siteSpace' => 'E',
            'description' => 'F',
            'projectTypeId' => null,
            'categoryId' => null,
            'planLevel' => 'Standard',
            'quotationType' => quotationTypeVal,
            'totalBudget' => 1000,
            'rooms' => new List<Object>(),
            'selectedRoomDesigns' => new List<Object>()
        };

        Boolean caught = false;
        try {
            Test.startTest();
            InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();
        } catch (AuraHandledException e) {
            caught = true;
        }

        System.assertEquals(true, caught, 'Second submission should fail');
    }

    /* ------------------------------------------
       Test: fetchLeadForAutoRequest
       ------------------------------------------ */
    @IsTest
    static void testFetchLeadForAutoRequest() {
        Lead ld = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        Lead result = InteriorAutoProjectRequestService.fetchLeadForAutoRequest(ld.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Returned Lead should not be null');
        System.assertEquals(ld.Id, result.Id, 'Lead Id mismatch');
    }

    @IsTest
    static void testFetchLeadForAutoRequestNullId() {
        Boolean caught = false;
        try {
            InteriorAutoProjectRequestService.fetchLeadForAutoRequest(null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assertEquals(true, caught, 'Null Id should throw AuraHandledException');
    }

    /* ------------------------------------------
       Test: fetchExistingRequest
       ------------------------------------------ */
    @IsTest
    static void testFetchExistingRequest() {

        Lead ld = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        InteriorAutoProjectRequestService.ExistingRequestDTO dto =
            InteriorAutoProjectRequestService.fetchExistingRequest(ld.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assert(dto.rooms.size() > 0, 'Rooms should not be empty');
        System.assert(dto.roomDesigns.size() > 0, 'Designs should not be empty');
    }

    @IsTest
    static void testFetchExistingRequestNullId() {
        Boolean caught = false;
        try {
            InteriorAutoProjectRequestService.fetchExistingRequest(null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assertEquals(true, caught, 'Null Id should throw AuraHandledException');
    }
}
