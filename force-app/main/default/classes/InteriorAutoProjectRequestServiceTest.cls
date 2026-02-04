/**
 * @description       : Unit tests for InteriorAutoProjectRequestService.
 *                      Covers:
 *                      - saveRequest() main happy path (lead update + child delete/insert + file copy)
 *                      - saveRequest() defaults (quantity defaulting)
 *                      - saveRequest() guard rails (double submission + null payload + missing leadId)
 *                      - saveRequest() empty children behavior (deletes existing)
 *                      - fetchLeadForAutoRequest() success + exception paths
 *                      - fetchExistingRequest() DTO population + exception paths
 *                      - Utility helpers: isEmpty(), nvl(), formatAmount()
 *
 *                      Note:
 *                      - Test data is created in @TestSetup to avoid re-creating records per test.
 *                      - Uses TestDataUtility for consistent Lead + ContentVersion creation/linking.
 *
 * @author            : 
 * @group             : Arelia Living
 * @last modified on  : 2026-01-30
 * @last modified by  : 
**/
@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ApexAssertionsShouldIncludeMessage')
private class InteriorAutoProjectRequestServiceTest {

    /* =========================================================
       TEST DATA SETUP
       ========================================================= */
    @TestSetup
    static void setupData() {
        // Create a standard user for running tests
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'standt',
            Email = 'standarduser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'standarduser' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        System.runAs(testUser) {
            // 1. Create Lead using your Utility
            Lead ld = TestDataUtility.createLead('AutoRequest Test');
            // Update fields required for the Service class logic
            ld.Email = 'test@example.com';
            ld.Phone = '555-555-5555';
            ld.Project_Request_Submitted__c = false;
            update ld;

            // 2. Create Master Data (Room & Design)
            Interior_Room__c room = new Interior_Room__c(Name = 'Living Room');
            insert room;

            Interior_Design__c design = new Interior_Design__c(Name = 'Luxury Design');
            insert design;

            // 3. Create Existing Request Records
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

            // 4. Create a File and Link it to the DESIGN
            ContentVersion cv = TestDataUtility.createContentVersion('Design Spec', 'Test File Content Data');
            TestDataUtility.linkFileToRecord(cv.Id, design.Id);
        }
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
    }

    /* =========================================================
       TESTS: SAVE REQUEST (Main Logic)
       ========================================================= */

    @IsTest
    static void testSaveRequestHappyPath() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = [SELECT Id FROM Lead LIMIT 1];
            Interior_Room__c room = [SELECT Id FROM Interior_Room__c LIMIT 1];
            Interior_Design__c design = [SELECT Id FROM Interior_Design__c LIMIT 1];

            List<Object> rooms = new List<Object>{
                new Map<String, Object>{
                    'roomId' => room.Id,
                    'quantity' => 5
                }
            };

            List<Object> designs = new List<Object>{
                new Map<String, Object>{
                    'roomId' => room.Id,
                    'designId' => design.Id,
                    'quantity' => 2,
                    'lineAmount' => 5000.50
                }
            };

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'firstName' => 'John',
                'lastName' => 'Doe',
                'email' => 'john.doe@test.com',
                'phone' => '1234567890',
                'company' => 'JD Corp',
                'address' => '123 Main St',
                'siteSpace' => '2 BHK',
                'description' => 'Full Reno',
                'totalBudget' => 50000,
                'planLevel' => 'Standard',
                'quotationType' => 'Manual',
                'projectTypeId' => null,
                'categoryId' => null,
                'rooms' => rooms,
                'selectedRoomDesigns' => designs
            };

            Test.startTest();
            Id resultId = InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            Lead updatedLead = [SELECT FirstName, LastName, Site_Location__c, Project_Request_Submitted__c, Estimated_Budget__c FROM Lead WHERE Id = :resultId];
            System.assertEquals('John', updatedLead.FirstName, 'Lead FirstName should be updated');
            System.assertEquals('Doe', updatedLead.LastName, 'Lead LastName should be updated');
            System.assertEquals(50000, updatedLead.Estimated_Budget__c, 'Budget should be updated');
            System.assertEquals(true, updatedLead.Project_Request_Submitted__c, 'Submitted flag should be true');

            List<Interior_Request_Room__c> newRooms = [SELECT Quantity__c FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
            System.assertEquals(1, newRooms.size(), 'Should have exactly 1 room record (old one deleted)');
            System.assertEquals(5, newRooms[0].Quantity__c, 'Room quantity should be updated to 5');

            List<Interior_Request_Room_Design__c> newDesigns = [SELECT Design_Amount__c FROM Interior_Request_Room_Design__c WHERE Lead__c = :ld.Id];
            System.assertEquals(1, newDesigns.size(), 'Should have exactly 1 design record');
            System.assertEquals(5000.50, newDesigns[0].Design_Amount__c, 'Design amount should be updated');

            List<ContentDocumentLink> leadFiles = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :ld.Id];
            System.assert(leadFiles.size() > 0, 'File linked to Design should have been copied to the Lead');
        }
    }

    @IsTest
    static void testSaveRequestWithDefaults() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = [SELECT Id FROM Lead LIMIT 1];
            Interior_Room__c room = [SELECT Id FROM Interior_Room__c LIMIT 1];

            List<Object> rooms = new List<Object>{
                new Map<String, Object>{ 'roomId' => room.Id }
            };
            List<Object> designs = new List<Object>{
                new Map<String, Object>{ 'roomId' => room.Id, 'designId' => null }
            };

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'lastName' => 'Doe',
                'rooms' => rooms,
                'selectedRoomDesigns' => designs
            };

            Test.startTest();
            InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            List<Interior_Request_Room__c> newRooms = [SELECT Quantity__c FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
            System.assertEquals(1, newRooms[0].Quantity__c, 'Should default quantity to 1 when missing in payload');
        }
    }

    @IsTest
    static void testSaveRequestDoubleSubmission() {
        User u = getTestUser();
        System.runAs(u) {
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
            }
            Test.stopTest();

            System.assertEquals(true, caught, 'Should block double submission');
        }
    }

    @IsTest
    static void testSaveRequestValidations() {
        User u = getTestUser();
        System.runAs(u) {
            // 1. Test Null Payload
            try {
                InteriorAutoProjectRequestService.saveRequest(null);
                System.assert(false, 'Should throw exception on null payload');
            } catch (AuraHandledException e) {
                System.assert(true);
            }

            // 2. Test Missing Lead Id
            Map<String, Object> req = new Map<String, Object>{ 'firstName' => 'Test' };
            try {
                InteriorAutoProjectRequestService.saveRequest(req);
                System.assert(false, 'Should throw exception on missing Lead Id');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void testSaveRequestEmptyChildren() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = [SELECT Id, LastName FROM Lead LIMIT 1];

            Map<String, Object> req = new Map<String, Object>{
                'leadId' => ld.Id,
                'lastName' => 'Smith',
                'rooms' => new List<Object>(),
                'selectedRoomDesigns' => new List<Object>()
            };

            Test.startTest();
            InteriorAutoProjectRequestService.saveRequest(req);
            Test.stopTest();

            Integer roomCount = [SELECT Count() FROM Interior_Request_Room__c WHERE Lead__c = :ld.Id];
            System.assertEquals(0, roomCount, 'All rooms should be removed');
        }
    }

    /* =========================================================
       TESTS: FETCH METHODS (Read Operations)
       ========================================================= */

    @IsTest
    static void testFetchLeadForAutoRequest() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = [SELECT Id FROM Lead LIMIT 1];

            Test.startTest();
            Lead result = InteriorAutoProjectRequestService.fetchLeadForAutoRequest(ld.Id);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return lead record');
            System.assertEquals(ld.Id, result.Id, 'Ids should match');
        }
    }

    @IsTest
    static void testFetchLeadExceptions() {
        User u = getTestUser();
        System.runAs(u) {
            try {
                InteriorAutoProjectRequestService.fetchLeadForAutoRequest(null);
                System.assert(false, 'Should throw exception on null id');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void testFetchExistingRequest() {
        User u = getTestUser();
        System.runAs(u) {
            Lead ld = [SELECT Id FROM Lead LIMIT 1];

            Test.startTest();
            InteriorAutoProjectRequestService.ExistingRequestDTO dto =
                InteriorAutoProjectRequestService.fetchExistingRequest(ld.Id);
            Test.stopTest();

            System.assertNotEquals(null, dto, 'DTO should return');
            System.assertEquals(1, dto.rooms.size(), 'Should return 1 existing room from Setup');
            System.assertEquals(1, dto.roomDesigns.size(), 'Should return 1 existing design from Setup');
        }
    }

    @IsTest
    static void testFetchExistingRequestExceptions() {
        User u = getTestUser();
        System.runAs(u) {
            try {
                InteriorAutoProjectRequestService.fetchExistingRequest(null);
                System.assert(false, 'Should throw exception on null id');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    /* =========================================================
       TESTS: UTILITY HELPERS
       ========================================================= */

    @IsTest
    static void testUtilityHelpers() {
        User u = getTestUser();
        System.runAs(u) {
            // 1. Test isEmpty(List<String>)
            System.assertEquals(true, InteriorAutoProjectRequestService.isEmpty(null), 'isEmpty should return true for null list');
            System.assertEquals(true, InteriorAutoProjectRequestService.isEmpty(new List<String>()), 'isEmpty should return true for empty list');
            System.assertEquals(false, InteriorAutoProjectRequestService.isEmpty(new List<String>{'A'}), 'isEmpty should return false for populated list');

            // 2. Test nvl(String)
            System.assertEquals('Not specified', InteriorAutoProjectRequestService.nvl(null), 'nvl should return default for null input');
            System.assertEquals('Valid Value', InteriorAutoProjectRequestService.nvl('Valid Value'), 'nvl should return original string');

            // 3. Test formatAmount(Decimal)
            System.assertEquals('', InteriorAutoProjectRequestService.formatAmount(null), 'formatAmount should return empty string for null');
            System.assertEquals('0.00', InteriorAutoProjectRequestService.formatAmount(0), 'Should format zero');
            System.assertEquals('500.00', InteriorAutoProjectRequestService.formatAmount(500), 'Should format simple hundreds');
            System.assertEquals('1,000.00', InteriorAutoProjectRequestService.formatAmount(1000), 'Should add comma for thousands');
            System.assertEquals('12,345.67', InteriorAutoProjectRequestService.formatAmount(12345.67), 'Should format tens of thousands');
            System.assertEquals('1,000,000.00', InteriorAutoProjectRequestService.formatAmount(1000000), 'Should handle millions (multiple commas)');
        }
    }
}