@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ApexAssertionsShouldIncludeMessage')
private class InteriorAutoProjectRequestServiceTest {

    /* =========================================================
       TEST DATA SETUP
       ========================================================= */
    @TestSetup
    static void setupData() {
        // 1. Create Lead using Utility
        Lead ld = TestDataUtility.createLead('AutoRequest Test');
        ld.Email = 'test@example.com';
        ld.Project_Request_Submitted__c = false;
        // Ensure required fields are present for update
        ld.Company = 'Test Co';
        update ld;

        // 2. Create Master Data (Room & Design)
        // Standard DML used as specific utility methods for these custom objects might not exist
        Interior_Room__c room = new Interior_Room__c(Name = 'Living Room');
        insert room;

        Interior_Design__c design = new Interior_Design__c(Name = 'Luxury Design');
        insert design;

        // 3. Create Existing Request Records (To test fetchExisting and delete logic)
        insert new Interior_Request_Room__c(
            Lead__c = ld.Id,
            Interior_Room__c = room.Id,
            Quantity__c = 1
        );

        insert new Interior_Request_Room_Design__c(
            Lead__c = ld.Id,
            Interior_Room__c = room.Id,
            Interior_Design__c = design.Id,
            Quantity__c = 1,
            Design_Amount__c = 100
        );

        // 4. Create a File linked to the DESIGN
        // This is critical to test the copyDesignFilesToLead method
        ContentVersion cv = TestDataUtility.createContentVersion('Design Spec', 'Spec Data');
        TestDataUtility.linkFileToRecord(cv.Id, design.Id);
    }

    /* =========================================================
       TESTS
       ========================================================= */

    /**
     * @description Tests the full save flow: Updates Lead, Replaces Children, Copies Files.
     * This single test covers the majority of the service class logic.
     */
    @IsTest
    static void testSaveRequest_HappyPath() {
        Lead ld = [SELECT Id FROM Lead LIMIT 1];
        Interior_Room__c room = [SELECT Id FROM Interior_Room__c LIMIT 1];
        Interior_Design__c design = [SELECT Id FROM Interior_Design__c LIMIT 1];

        // Prepare Payload
        // We use Maps to simulate the JSON object coming from LWC
        List<Object> rooms = new List<Object>{
            new Map<String, Object>{
                'roomId' => room.Id,
                'quantity' => 5
            }
        };

        List<Object> designs = new List<Object>{
            new Map<String, Object>{
                'roomId' => room.Id,
                'designId' => design.Id, // Contains the file we want to copy
                'quantity' => 2,
                'lineAmount' => 5000.50
            }
        };

        Map<String, Object> req = new Map<String, Object>{
            'leadId' => ld.Id,
            'firstName' => 'John',
            'lastName' => 'Doe', // Required field
            'email' => 'john.doe@test.com',
            'phone' => '1234567890',
            'company' => 'JD Corp', // Required field
            'address' => '123 Main St',
            'siteSpace' => '2 BHK',
            'description' => 'Full Reno',
            'totalBudget' => 50000,
            'planLevel' => 'Standard',
            'quotationType' => 'Manual Quotation',
            'projectTypeId' => null, // Cover null handling in getStr
            'categoryId' => null,
            'rooms' => rooms,
            'selectedRoomDesigns' => designs
        };

        Test.startTest();
        Id resultId = InteriorAutoProjectRequestService.saveRequest(req);
        Test.stopTest();

        // 1. Validate Lead Update
        Lead updatedLead = [SELECT FirstName, LastName, Site_Location__c, Project_Request_Submitted__c, Estimated_Budget__c FROM Lead WHERE Id = :resultId];
        System.assertEquals('John', updatedLead.FirstName, 'Lead FirstName should be updated');
        System.assertEquals('Doe', updatedLead.LastName, 'Lead LastName should be updated');
        System.assertEquals('123 Main St', updatedLead.Site_Location__c, 'Lead Address should be mapped');
        System.assertEquals(50000, updatedLead.Estimated_Budget__c, 'Budget should be updated');
        System.assertEquals(true, updatedLead.Project_Request_Submitted__c, 'Submitted flag should be true');

        // 2. Validate Child Records Replaced
        // Previous setup had 1 room qty 1. New payload has 1 room qty 5.
        List<Interior_Request_Room__c> newRooms = [SELECT Quantity__c FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
        System.assertEquals(1, newRooms.size(), 'Should have 1 room record');
        System.assertEquals(5, newRooms[0].Quantity__c, 'Room quantity should be updated/replaced');

        List<Interior_Request_Room_Design__c> newDesigns = [SELECT Design_Amount__c FROM Interior_Request_Room_Design__c WHERE Lead__c = :ld.Id];
        System.assertEquals(1, newDesigns.size(), 'Should have 1 design record');
        System.assertEquals(5000.50, newDesigns[0].Design_Amount__c, 'Design amount should be updated');

        // 3. Validate File Copy (Design -> Lead)
        // The setup created a file on the Design. The service should copy it to the Lead.
        List<ContentDocumentLink> leadFiles = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id];
        System.assert(leadFiles.size() > 0, 'File linked to Design should have been copied to the Lead');
    }

    /**
     * @description Tests attempting to submit for a Lead that is already submitted.
     */
    @IsTest
    static void testSaveRequest_DoubleSubmission() {
        Lead ld = [SELECT Id, LastName, Company FROM Lead LIMIT 1];
        ld.Project_Request_Submitted__c = true;
        update ld;

        Map<String, Object> req = new Map<String, Object>{ 
            'leadId' => ld.Id,
            'lastName' => ld.LastName,
            'company' => ld.Company
        };

        Boolean caught = false;
        Test.startTest();
        try {
            InteriorAutoProjectRequestService.saveRequest(req);
        } catch (AuraHandledException e) {
            caught = true;
            // Note: AuraHandledException messages are sometimes obfuscated in tests as "Script-thrown exception".
            // We verify the exception type primarily.
            System.assertNotEquals(null, e, 'Exception should be thrown');
        }
        Test.stopTest();

        System.assertEquals(true, caught, 'Should block double submission');
    }

    /**
     * @description Tests validations for empty payload or missing Lead Id.
     */
    @IsTest
    static void testSaveRequest_Validations() {
        // 1. Null Payload
        try {
            InteriorAutoProjectRequestService.saveRequest(null);
            System.assert(false, 'Should throw exception on null payload');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        // 2. Missing Lead Id
        Map<String, Object> req = new Map<String, Object>{ 'firstName' => 'Test' };
        try {
            InteriorAutoProjectRequestService.saveRequest(req);
            System.assert(false, 'Should throw exception on missing Lead Id');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    /**
     * @description Tests clearing selections (sending empty lists).
     * IMPORTANT: Must provide required Lead fields to avoid DmlException.
     */
    @IsTest
    static void testSaveRequest_EmptyChildren() {
        Lead ld = [SELECT Id, LastName, Company FROM Lead LIMIT 1];

        Map<String, Object> req = new Map<String, Object>{
            'leadId' => ld.Id,
            'lastName' => ld.LastName, // Required
            'company' => ld.Company,   // Required
            'rooms' => new List<Object>(), // Empty List
            'selectedRoomDesigns' => new List<Object>() // Empty List
        };

        Test.startTest();
        InteriorAutoProjectRequestService.saveRequest(req);
        Test.stopTest();

        // Should have deleted existing ones from Setup and created 0 new ones
        Integer roomCount = [SELECT Count() FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
        Integer designCount = [SELECT Count() FROM Interior_Request_Room_Design__c WHERE Lead__c = :ld.Id];

        System.assertEquals(0, roomCount, 'All rooms should be removed');
        System.assertEquals(0, designCount, 'All designs should be removed');
    }

    /* =========================================================
       DATA RETRIEVAL TESTS
       ========================================================= */

    @IsTest
    static void testFetchLeadForAutoRequest() {
        Lead ld = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        Lead result = InteriorAutoProjectRequestService.fetchLeadForAutoRequest(ld.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return lead');
        System.assertEquals(ld.Id, result.Id, 'Ids should match');
    }

    @IsTest
    static void testFetchLeadForAutoRequest_Errors() {
        try {
            InteriorAutoProjectRequestService.fetchLeadForAutoRequest(null);
            System.assert(false, 'Should throw exception on null id');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testFetchExistingRequest() {
        Lead ld = [SELECT Id FROM Lead LIMIT 1];

        Test.startTest();
        InteriorAutoProjectRequestService.ExistingRequestDTO dto = 
            InteriorAutoProjectRequestService.fetchExistingRequest(ld.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should return');
        System.assertEquals(1, dto.rooms.size(), 'Should return 1 existing room');
        System.assertEquals(1, dto.roomDesigns.size(), 'Should return 1 existing design');
    }

    @IsTest
    static void testFetchExistingRequest_Errors() {
        try {
            InteriorAutoProjectRequestService.fetchExistingRequest(null);
            System.assert(false, 'Should throw exception on null id');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}