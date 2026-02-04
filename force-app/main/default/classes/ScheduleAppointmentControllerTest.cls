@isTest
public class ScheduleAppointmentControllerTest {

    @testSetup
    static void setupData() {
        // 1. Create Supervisor User
        User supervisor = TestDataUtility.createSupervisorUser('SupUser');
        
        // Ensure Supervisor has the required Phone field populated
        supervisor.Phone = '555-123-4567';
        update supervisor;

        // 2. Create Email Templates (in runAs to avoid Mixed DML)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = new List<EmailTemplate>();
            
            EmailTemplate t1 = new EmailTemplate();
            t1.DeveloperName = Label.Arelia_Living_Lead_Site_Visiting_Email_Template;
            t1.Name = 'Lead Template';
            t1.Subject = 'Lead Visit {{{appointmentDate}}}';
            t1.HtmlValue = 'Hi {{{Recipient.Name}}}, visit on {{{appointmentDate}}} at {{{timeSlot}}}';
            t1.TemplateType = 'text';
            t1.FolderId = UserInfo.getUserId();
            templates.add(t1);

            EmailTemplate t2 = new EmailTemplate();
            t2.DeveloperName = Label.Arelia_Living_Supervisor_Site_Visiting_Email_Template;
            t2.Name = 'Supervisor Template';
            t2.Subject = 'Sup Visit {{{appointmentDate}}}';
            t2.HtmlValue = 'Hi {{{Recipient.Name}}}, lead visit {{{leadName}}} on {{{appointmentDate}}}';
            t2.TemplateType = 'text';
            t2.FolderId = UserInfo.getUserId();
            templates.add(t2);

            insert templates;
        }

        // 3. Create Lead assigned to Supervisor
        Lead l = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'test@lead.com',
            Supervisor_User__c = supervisor.Id,
            Status = 'Open'
        );
        insert l;
    }

    @isTest
    static void testScheduleSuccess() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
        
        String futureDate = String.valueOf(Date.today().addDays(5));
        
        // FIX: Dynamically fetch a VALID slot and type from the system to avoid Restricted Picklist errors
        List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        List<String> validTypes = ScheduleAppointmentController.getAppointmentTypesPicklistValues();
        
        // Fallback to defaults if list is somehow empty (unlikely)
        String slot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];
        String type = validTypes.isEmpty() ? 'In Person' : validTypes[0];

        Test.startTest();
        ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
            l.Id, 
            l.Supervisor_User__c, 
            futureDate, 
            slot, 
            type
        );
        Test.stopTest();

        // Verify Lead was updated
        Lead updatedLead = [SELECT Appointment_Date__c, Appointment_Time_Slots__c, Appointment_Confirmation_Type__c, Appointment_Sent_date__c FROM Lead WHERE Id = :l.Id];
        System.assertEquals(Date.today().addDays(5), updatedLead.Appointment_Date__c, 'Appointment Date should be updated');
        System.assertEquals(slot, updatedLead.Appointment_Time_Slots__c, 'Time Slot should be updated');
        System.assertEquals(type, updatedLead.Appointment_Confirmation_Type__c, 'Confirmation Type should be updated');
        System.assertEquals(System.today(), updatedLead.Appointment_Sent_date__c, 'Sent Date should be today');
    }

    @isTest
    static void testSlotConflict() {
        Lead l1 = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
        
        // FIX: Dynamically fetch valid slot
        List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        String conflictSlot = validSlots.isEmpty() ? '2PM-3PM' : validSlots[0];

        // Create a SECOND lead for the conflict
        Lead l2 = new Lead(
            FirstName = 'Conflict',
            LastName = 'Lead',
            Company = 'Conflict Co',
            Email = 'conflict@test.com',
            Supervisor_User__c = l1.Supervisor_User__c, 
            Appointment_Status__c = 'Approved', 
            Appointment_Date__c = Date.today().addDays(3),
            Appointment_Time_Slots__c = conflictSlot
        );
        insert l2;

        Test.startTest();
        try {
            // Try to schedule l1 for the same time
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l1.Id, 
                l1.Supervisor_User__c, 
                String.valueOf(Date.today().addDays(3)), 
                conflictSlot, 
                'Virtual' // Type doesn't matter for this check as it fails before update
            );
            System.assert(false, 'Should have thrown exception due to conflict');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException was thrown');
        }
        Test.stopTest();
    }

    @isTest
    static void testInputValidationMissingFields() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
        
        // Helper to get a valid slot string
        List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

        Test.startTest();
        // 1. Missing Date
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(l.Id, l.Supervisor_User__c, null, validSlot, 'Type');
            System.assert(false, 'Should fail missing date');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for missing date');
        }

        // 2. Missing Slot
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(l.Id, l.Supervisor_User__c, '2025-01-01', null, 'Type');
            System.assert(false, 'Should fail missing slot');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for missing slot');
        }

        // 3. Missing Type
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(l.Id, l.Supervisor_User__c, '2025-01-01', validSlot, null);
            System.assert(false, 'Should fail missing type');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for missing type');
        }
        Test.stopTest();
    }

    @isTest
    static void testInputValidationPastDate() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
        String pastDate = String.valueOf(Date.today().addDays(-1));
        
        List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

        Test.startTest();
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id, l.Supervisor_User__c, pastDate, validSlot, 'In Person'
            );
            System.assert(false, 'Should fail on past date');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected AuraHandledException for past date');
        }
        Test.stopTest();
    }

    @isTest
    static void testDataValidationMissingSupervisor() {
        List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

        // Create a lead WITHOUT a supervisor
        Lead orphanedLead = new Lead(
            FirstName = 'Orphan',
            LastName = 'Lead',
            Company = 'Orphan Co',
            Email = 'orphan@test.com'
        );
        insert orphanedLead;

        Test.startTest();
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                orphanedLead.Id, null, String.valueOf(Date.today().addDays(2)), validSlot, 'Type'
            );
            System.assert(false, 'Should fail due to missing supervisor');
        } catch(AuraHandledException e) {
            System.assert(true, 'Expected exception due to missing supervisor'); 
        }
        Test.stopTest();
    }
    
    @isTest
    static void testPicklistHelpers() {
        Test.startTest();
        List<String> slots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        List<String> types = ScheduleAppointmentController.getAppointmentTypesPicklistValues();
        Test.stopTest();
        
        System.assertNotEquals(null, slots, 'Time Slots should return a list');
        System.assertNotEquals(null, types, 'Appointment Types should return a list');
    }
}