@isTest
public class ScheduleAppointmentonOppControllerTest {

    @testSetup
    static void setupData() {
        // 1. Create Supervisor using Utility
        User supervisor = TestDataUtility.createSupervisorUser('SupOpp');
        // Controller validation requires Supervisor Phone
        supervisor.Phone = '555-010-9999';
        update supervisor;

        // 2. Create Templates using Utility
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String clientLabel = Label.Arelia_Living_Lead_Site_Re_Visiting_Email_Template;
            if (String.isNotBlank(clientLabel)) {
                TestDataUtility.createSpecificEmailTemplate(
                    clientLabel, 
                    'Client Revisit Template', 
                    'Appointment Confirmed: {{{appointmentDate}}}'
                );
            }

            String supTplDevName = Label.Arelia_Living_Supervisor_Site_Re_Visiting_Email_Template;
            if (String.isNotBlank(supTplDevName)) {
                TestDataUtility.createSpecificEmailTemplate(
                    supTplDevName, 
                    'Supervisor Revisit Template', 
                    'New Appointment: {{{appointmentDate}}}'
                );
            }
        }

        // 3. Create Contact
        Contact c = TestDataUtility.createContact('TestClient', 'client@test.com', 'password123');

        // 4. Create Opportunity using Utility
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = null; 
        params.slot = null;
        params.contactId = c.Id; 
        
        Opportunity opp = TestDataUtility.createAppointmentOpportunity(params);

        // 5. Update Opportunity with fields required by Controller logic
        opp.Email__c = 'client@test.com'; 
        opp.Lead_Name__c = 'Test Client Name'; 
        opp.Re_Visit_Appointmnet_Confirmation__c = false;
        opp.StageName = 'Qualification'; 
        update opp;
    }

    @isTest
    static void testScheduleSuccess() {
        Opportunity opp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        
        String futureDate = String.valueOf(Date.today().addDays(5));
        
        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        String slot = validSlots.isEmpty() ? '9 AM - 10 AM' : validSlots[0];
        
        List<String> validTypes = ScheduleAppointmentonOppController.getAppointmentTypesPicklistValues();
        String type = validTypes.isEmpty() ? 'Virtual' : validTypes[0];

        Test.startTest();
        ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
            opp.Id, futureDate, slot, type
        );
        Test.stopTest();

        // Verification
        Opportunity updatedOpp = [SELECT Re_Visit_Appointment_Date__c, Re_Visit_Appointment_Time_Slots__c, Re_Visit_Site_Appointment_Status__c, Re_Visit_Appointmnet_Confirmation__c FROM Opportunity WHERE Id = :opp.Id];
        
        System.assertEquals(Date.today().addDays(5), updatedOpp.Re_Visit_Appointment_Date__c, 'Date should be updated');
        System.assertEquals(slot, updatedOpp.Re_Visit_Appointment_Time_Slots__c, 'Slot should be updated');
        System.assertEquals('Pending', updatedOpp.Re_Visit_Site_Appointment_Status__c, 'Status should be Pending');
        System.assertEquals(true, updatedOpp.Re_Visit_Appointmnet_Confirmation__c, 'Confirmation should be true');
    }

    @isTest
    static void testSlotConflict() {
        Opportunity targetOpp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1]; 
        
        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        String conflictSlot = validSlots.isEmpty() ? '2 PM - 3 PM' : validSlots[0];
        Date conflictDate = Date.today().addDays(3);

        // Create a "Blocker" Opportunity for the SAME Supervisor
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = targetOpp.Supervisor_User__c; 
        params.status = 'Approved'; 
        params.apptDate = conflictDate;
        params.slot = conflictSlot;
        params.contactId = c.Id;

        Opportunity blocker = TestDataUtility.createAppointmentOpportunity(params);
        blocker.Re_Visit_Site_Appointment_Status__c = 'Approved';
        update blocker;

        Test.startTest();
        try {
            ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
                targetOpp.Id, 
                String.valueOf(conflictDate), 
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
        
        // 1. Set Confirmation to TRUE to trigger validation
        opp.Re_Visit_Appointmnet_Confirmation__c = true; 
        update opp;

        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        String slot = validSlots.isEmpty() ? '9 AM - 10 AM' : validSlots[0];

        Test.startTest();
        try {
            ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
                opp.Id, String.valueOf(Date.today().addDays(2)), slot, 'Virtual'
            );
            System.assert(false, 'Should fail if already confirmed');
        } catch(AuraHandledException e) {
            System.assert(true, 'Caught expected AuraHandledException');
        }
        Test.stopTest();
    }

    @isTest
    static void testValidationClosedWon() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'SupOpp' LIMIT 1];
        Opportunity opp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        
        // 1. Create a Vendor for the agreement check
        Vendor__c vendor = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'v@test.com');

        // 2. Satisfy Project Creation Gates
        opp.Client_Agreement_Signed__c = true;
        opp.All_Vendors_Agreement_Completed__c = true;
        // Make Supervisor the owner so runAs works correctly and Flow ownership transfer doesn't fail
        opp.OwnerId = supervisor.Id;
        update opp;

        // 3. Create Signed Vendor Opportunity
        Vendor_Opportunity__c vo = new Vendor_Opportunity__c(
            Opportunity__c = opp.Id,
            Vendor__c = vendor.Id,
            Vendor_Agreement_Signed__c = true 
        );
        insert vo;

        // 4. Update Stage to Closed Won AS SUPERVISOR
        // This ensures the created Project is owned by Supervisor, preventing "TRANSFER_REQUIRES_READ" error in Flow.
        System.runAs(supervisor) {
            opp.StageName = 'Closed Won';
            update opp;
        }

        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        String slot = validSlots.isEmpty() ? '9 AM - 10 AM' : validSlots[0];

        Test.startTest();
        try {
            ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails(
                opp.Id, String.valueOf(Date.today().addDays(2)), slot, 'Virtual'
            );
            System.assert(false, 'Should fail if Closed Won');
        } catch(AuraHandledException e) {
            System.assert(true, 'Caught expected AuraHandledException for Closed Won');
        }
        Test.stopTest();
    }

    @isTest
    static void testAvailableSlotsFilter() {
        Opportunity opp = [SELECT Id, Supervisor_User__c FROM Opportunity LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        List<String> validSlots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        if (validSlots.isEmpty()) {
            return; 
        }

        String slotToBlock = validSlots[0];
        Date testDate = Date.today().addDays(10);

        // Create Blocker
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = opp.Supervisor_User__c;
        params.status = 'Approved';
        params.apptDate = testDate;
        params.slot = slotToBlock;
        params.contactId = c.Id;

        Opportunity blocker = TestDataUtility.createAppointmentOpportunity(params);
        
        // Ensure status field used by getAvailableTimeSlotsOpp logic is set
        blocker.Appointment_Status__c = 'Approved'; 
        blocker.Re_Visit_Site_Appointment_Status__c = 'Approved';
        update blocker;

        Test.startTest();
        List<String> available = ScheduleAppointmentonOppController.getAvailableTimeSlotsOpp(testDate, opp.Id);
        Test.stopTest();

        System.assert(!available.contains(slotToBlock), 'Available slots should not contain the blocked slot');
    }

    @isTest
    static void testHelpers() {
        List<String> types = ScheduleAppointmentonOppController.getAppointmentTypesPicklistValues();
        System.assertNotEquals(null, types, 'Types list should not be null');
        
        List<String> slots = ScheduleAppointmentonOppController.getTimeSlotsPicklistValues();
        System.assertNotEquals(null, slots, 'Slots list should not be null');
    }
}