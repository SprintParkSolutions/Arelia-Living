@isTest
public class ScheduleAppointmentonOppControllerTest {

    @testSetup
    static void setupData() {
        // 1. Create Supervisor using Utility
        // Note: Utility sets default fields; we update Phone as required by Controller
        User supervisor = TestDataUtility.createSupervisorUser('SupOpp');
        supervisor.Phone = '555-999-8888'; 
        update supervisor;

        // 2. Create Templates using Utility
        // Wrapped in runAs to avoid Mixed DML (Setup vs Non-Setup objects)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String clientLabel = Label.Arelia_Living_Lead_Site_Re_Visiting_Email_Template;
            if (String.isNotBlank(clientLabel)) {
                TestDataUtility.createSpecificEmailTemplate(clientLabel, 'Client Tpl', 'Test Subject');
            }
            
            String supLabel = Label.Arelia_Living_Supervisor_Site_Re_Visiting_Email_Template;
            if (String.isNotBlank(supLabel)) {
                TestDataUtility.createSpecificEmailTemplate(supLabel, 'Sup Tpl', 'Test Subject');
            }
        }

        // 3. Create Contact using Utility (Required for Opportunity Primary Contact)
        Contact c = TestDataUtility.createContact('TestClient', 'client@test.com');

        // 4. Create Opportunity using Utility and Wrapper
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = null; // Not scheduled yet
        params.slot = null;
        params.contactId = c.Id; // Sets Primary_Contact__c which helps satisfy external triggers
        
        Opportunity opp = TestDataUtility.createAppointmentOpportunity(params);

        // 5. Update Opportunity with specific fields required by the Controller logic
        // (These fields are not set by the Utility method)
        opp.Email__c = 'client@test.com'; 
        opp.Lead_Name__c = 'Test Client Name'; // Prevents NPE in Email Template rendering
        opp.Re_Visit_Appointmnet_Confirmation__c = false;
        
        // Optional: Change Stage if 'Prospecting' (default in Utility) causes trigger issues
        opp.StageName = 'Qualification'; 
        update opp;
    }

    @isTest
    static void testScheduleSuccess() {
        Opportunity opp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        
        // Fetch valid slots dynamically to avoid Restricted Picklist errors
        String futureDate = String.valueOf(Date.today().addDays(5));
        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        List<String> validTypes = ScheduleAppointmentonOppController.getAppointmentTypesPicklistValues();
        
        String slot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];
        String type = validTypes.isEmpty() ? 'Virtual' : validTypes[0];

        Test.startTest();
        ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
            opp.Id, futureDate, slot, type
        );
        Test.stopTest();

        // Verification
        Opportunity updatedOpp = [SELECT Re_Visit_Appointment_Date__c, Re_Visit_Appointment_Time_Slots__c, Re_Visit_Site_Appointment_Status__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(Date.today().addDays(5), updatedOpp.Re_Visit_Appointment_Date__c, 'Date should be updated');
        System.assertEquals(slot, updatedOpp.Re_Visit_Appointment_Time_Slots__c, 'Slot should be updated');
        System.assertEquals('Pending', updatedOpp.Re_Visit_Site_Appointment_Status__c, 'Status should be Pending');
    }

    @isTest
    static void testSlotConflict() {
        Opportunity targetOpp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1]; // Reuse existing contact for blocker
        
        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        String conflictSlot = validSlots.isEmpty() ? '2PM-3PM' : validSlots[0];

        // 1. Create a "Blocker" Opportunity using Utility
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = targetOpp.Supervisor_User__c; // Same Supervisor
        params.status = 'Approved'; // This triggers the conflict check
        params.apptDate = Date.today().addDays(3);
        params.slot = conflictSlot;
        params.contactId = c.Id;

        Opportunity blocker = TestDataUtility.createAppointmentOpportunity(params);

        // Ensure legacy status field is also set if the controller queries it
        blocker.Appointment_Status__c = 'Approved';
        update blocker;

        Test.startTest();
        try {
            // 2. Try to schedule the target opp for the exact same time
            ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
                targetOpp.Id, 
                String.valueOf(Date.today().addDays(3)), 
                conflictSlot, 
                'Virtual'
            );
            System.assert(false, 'Should have thrown exception due to conflict');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected conflict exception');
        }
        Test.stopTest();
    }

    @isTest
    static void testValidationAlreadyConfirmed() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Re_Visit_Appointmnet_Confirmation__c = true; // Already confirmed
        update opp;

        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        String slot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

        Test.startTest();
        try {
            ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
                opp.Id, String.valueOf(Date.today().addDays(2)), slot, 'Type'
            );
            System.assert(false, 'Should fail if already confirmed');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected exception for already confirmed');
        }
        Test.stopTest();
    }

    @isTest
    static void testAvailableSlotsFilter() {
        Opportunity opp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        // Guard clause for missing picklist values
        if (validSlots.isEmpty()) {
            return; 
        }

        String slotToBlock = validSlots[0];
        Date testDate = Date.today().addDays(10);

        // 1. Create Blocker using Utility
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = opp.Supervisor_User__c;
        params.status = 'Approved';
        params.apptDate = testDate;
        params.slot = slotToBlock;
        params.contactId = c.Id;

        Opportunity blocker = TestDataUtility.createAppointmentOpportunity(params);
        
        // Ensure legacy status is set for query compatibility
        blocker.Appointment_Status__c = 'Approved';
        update blocker;

        Test.startTest();
        // 2. Fetch available slots
        List<String> available = ScheduleAppointmentonOppController.getAvailableTimeSlotsOpp(testDate, opp.Id);
        Test.stopTest();

        // 3. Assert the blocked slot is missing
        System.assert(!available.contains(slotToBlock), 'Available slots should not contain the blocked slot');
    }

    @isTest
    static void testHelpers() {
        // Verify picklist helpers return non-null lists
        List<String> types = ScheduleAppointmentonOppController.getAppointmentTypesPicklistValues();
        System.assertNotEquals(null, types, 'Types list should not be null');
        
        List<String> slots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        System.assertNotEquals(null, slots, 'Slots list should not be null');
    }
}