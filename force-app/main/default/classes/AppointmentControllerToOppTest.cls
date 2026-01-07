@isTest
public class AppointmentControllerToOppTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('oppSup');

        // 2. Create Contact (Required for Primary_Contact__c in email logic)
        TestDataUtility.createContact('Test Contact', 'testcontact@example.com');

        // 3. Create Email Templates (Mocking labels via developer name match)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            EmailTemplate t1 = new EmailTemplate(
                DeveloperName = 'Opp_Appt_Approved',
                Name = 'Opp Appt Approved',
                Subject = 'Approved',
                HtmlValue = '<html>Approved</html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            );
            
            EmailTemplate t2 = new EmailTemplate(
                DeveloperName = 'Opp_Appt_Rescheduled',
                Name = 'Opp Appt Rescheduled',
                Subject = 'Rescheduled',
                HtmlValue = '<html>Rescheduled</html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            );
            insert new List<EmailTemplate>{t1, t2};
        }
    }

    // ==========================================
    // AVAILABILITY LOGIC TESTS
    // ==========================================

    @isTest
    static void testGetAvailableSlotsNoConflicts() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        
        // Manual instantiation to fix ExcessiveParameterList
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = testDate;
        params.slot = null;
        params.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(params);

        Test.startTest();
        List<String> slots = AppointmentControllerToOpp.getAvailableTimeSlots(testDate, myOpp.Id);
        Test.stopTest();

        Assert.isNotNull(slots, 'Should return slots list');
        Assert.isFalse(slots.isEmpty(), 'Should have slots available');
    }

    @isTest
    static void testGetAvailableSlotsConflictWithOtherOpp() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        String blockedSlot = '10AM-11AM';

        // 1. Create BLOCKER Opp
        TestDataUtility.AppointmentOppParams blockerParams = new TestDataUtility.AppointmentOppParams();
        blockerParams.supervisorId = supervisor.Id;
        blockerParams.status = 'Approved';
        blockerParams.apptDate = testDate;
        blockerParams.slot = blockedSlot;
        blockerParams.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        TestDataUtility.createAppointmentOpportunity(blockerParams);

        // 2. Create MY Opp
        TestDataUtility.AppointmentOppParams myParams = new TestDataUtility.AppointmentOppParams();
        myParams.supervisorId = supervisor.Id;
        myParams.status = 'Pending';
        myParams.apptDate = testDate;
        myParams.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(myParams);

        Test.startTest();
        List<String> slots = AppointmentControllerToOpp.getAvailableTimeSlots(testDate, myOpp.Id);
        Test.stopTest();

        Assert.isFalse(slots.contains(blockedSlot), 'Slot should be blocked by another Opportunity');
    }

    @isTest
    static void testGetAvailableSlotsConflictWithLead() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        String blockedSlot = '2PM-3PM';

        // 1. Create BLOCKER Lead
        TestDataUtility.AppointmentLeadParams leadParams = new TestDataUtility.AppointmentLeadParams();
        leadParams.supervisorId = supervisor.Id;
        leadParams.status = 'Approved';
        leadParams.apptDate = testDate;
        leadParams.slot = blockedSlot;
        TestDataUtility.createAppointmentLead(leadParams);

        // 2. Create MY Opp
        TestDataUtility.AppointmentOppParams myParams = new TestDataUtility.AppointmentOppParams();
        myParams.supervisorId = supervisor.Id;
        myParams.status = 'Pending';
        myParams.apptDate = testDate;
        myParams.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(myParams);

        Test.startTest();
        List<String> slots = AppointmentControllerToOpp.getAvailableTimeSlots(testDate, myOpp.Id);
        Test.stopTest();

        Assert.isFalse(slots.contains(blockedSlot), 'Slot should be blocked by a Lead');
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        List<String> values = AppointmentControllerToOpp.getTimeSlotsPicklistValues();
        Test.stopTest();
        Assert.isNotNull(values, 'Should return picklist values');
    }

    // ==========================================
    // STATUS UPDATE TESTS
    // ==========================================

    @isTest
    static void testUpdateStatusApproved() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = testDate;
        params.slot = '9AM-10AM';
        params.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(params);

        Test.startTest();
        // Passing nulls for reschedule fields as we are approving
        AppointmentControllerToOpp.updateAppointmentStatus(myOpp.Id, 'Approved', null, null, null);
        Test.stopTest();

        Opportunity updated = [SELECT Re_Visit_Site_Appointment_Status__c FROM Opportunity WHERE Id = :myOpp.Id];
        Assert.areEqual('Approved', updated.Re_Visit_Site_Appointment_Status__c, 'Status should be Approved');
    }

    @isTest
    static void testUpdateStatusRescheduled() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date initialDate = Date.today().addDays(2);
        Date newDate = Date.today().addDays(5);
        String newSlot = '4PM-5PM';
        
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = initialDate;
        params.slot = '9AM-10AM';
        params.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(params);

        Test.startTest();
        AppointmentControllerToOpp.updateAppointmentStatus(myOpp.Id, 'Rescheduled', 'Busy', newDate, newSlot);
        Test.stopTest();

        Opportunity updated = [
            SELECT Re_Visit_Site_Appointment_Status__c, 
                   Re_Visit_Appointment_Rescheduled_Date__c, 
                   Re_Visit_Appointm_Rescheduled_Time_Slots__c 
            FROM Opportunity WHERE Id = :myOpp.Id
        ];
        Assert.areEqual('Rescheduled', updated.Re_Visit_Site_Appointment_Status__c, 'Status should be Rescheduled');
        Assert.areEqual(newDate, updated.Re_Visit_Appointment_Rescheduled_Date__c, 'Reschedule date should match');
        Assert.areEqual(newSlot, updated.Re_Visit_Appointm_Rescheduled_Time_Slots__c, 'Reschedule slot should match');
    }

    @isTest
    static void testUpdateStatusRescheduleConflict() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date targetDate = Date.today().addDays(5);
        String targetSlot = '10AM-11AM';

        // 1. Blocker Opp
        TestDataUtility.AppointmentOppParams blockerParams = new TestDataUtility.AppointmentOppParams();
        blockerParams.supervisorId = supervisor.Id;
        blockerParams.status = 'Approved';
        blockerParams.apptDate = targetDate;
        blockerParams.slot = targetSlot;
        blockerParams.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        TestDataUtility.createAppointmentOpportunity(blockerParams);

        // 2. My Opp
        TestDataUtility.AppointmentOppParams myParams = new TestDataUtility.AppointmentOppParams();
        myParams.supervisorId = supervisor.Id;
        myParams.status = 'Pending';
        myParams.apptDate = Date.today();
        myParams.slot = '9AM-10AM';
        myParams.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(myParams);

        Test.startTest();
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(myOpp.Id, 'Rescheduled', null, targetDate, targetSlot);
            Assert.fail('Should throw exception due to conflict');
        } catch(AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateStatusGuardClause() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        
        // Already Approved
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Approved';
        params.apptDate = Date.today();
        params.slot = '9AM-10AM';
        params.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity myOpp = TestDataUtility.createAppointmentOpportunity(params);

        Test.startTest();
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(myOpp.Id, 'Approved', null, null, null);
            Assert.fail('Should throw exception for already approved record');
        } catch(AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateStatusInvalidInputs() {
        // Create a dummy opportunity to use a valid ID (AvoidHardcodingId rule)
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = Date.today();
        params.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        Opportunity dummyOpp = TestDataUtility.createAppointmentOpportunity(params);
        
        Test.startTest();
        
        // 1. Missing ID
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(null, 'Approved', null, null, null);
            Assert.fail('Should fail on missing ID');
        } catch(Exception e) { 
            Assert.isNotNull(e, 'Exception expected for missing ID'); 
        }

        // 2. Missing Status (Using valid ID)
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(dummyOpp.Id, null, null, null, null);
            Assert.fail('Should fail on missing Status');
        } catch(Exception e) { 
            Assert.isNotNull(e, 'Exception expected for missing Status'); 
        }
        
        Test.stopTest();
    }
}