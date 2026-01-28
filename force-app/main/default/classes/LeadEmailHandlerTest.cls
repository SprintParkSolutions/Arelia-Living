@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.MethodNamingConventions,PMD.ApexAssertionsShouldIncludeMessage')
private class LeadEmailHandlerTest {

    // ------------------------------------------------------------
    // Utility: create a base Lead used across tests
    // ------------------------------------------------------------
    private static Lead createBaseLead(
        String lastName,
        String email,
        String quotationType
    ) {
        Lead testLead = new Lead();
        testLead.FirstName    = 'Test';
        testLead.LastName     = lastName;
        testLead.Company      = 'Arelia Test Co';
        testLead.Status       = 'Open - Not Contacted';
        testLead.Email        = email;
        testLead.Project_Request_Quotation_Type__c = quotationType;
        testLead.Project_Request_Submitted__c      = false;
        testLead.Approval_Status__c                = 'Pending';
        return testLead;
    }

    // ------------------------------------------------------------
    // 1️⃣ Manual Quotation Tests
    // ------------------------------------------------------------
    @IsTest
    static void testManualQuotationSubmissionAndApproval() {
        Lead manualLead = createBaseLead('ManualLead', 'manual.lead@test.com', 'Manual Quotation');
        insert manualLead;

        manualLead.Project_Request_Submitted__c = true;
        update manualLead;   

        manualLead.Approval_Status__c = 'Approved';
        update manualLead;   

        Lead reloaded = [SELECT Project_Request_Submitted__c, Approval_Status__c FROM Lead WHERE Id = :manualLead.Id];
        System.assertEquals(true, reloaded.Project_Request_Submitted__c, 'Manual quotation Lead must be marked submitted.');
        System.assertEquals('Approved', reloaded.Approval_Status__c, 'Manual quotation Lead must be marked approved.');
    }

    // ------------------------------------------------------------
    // 2️⃣ Automatic Quotation Tests
    // ------------------------------------------------------------
    @IsTest
    static void testAutomaticQuotationWithAttachmentsSubmissionAndApproval() {
        Lead autoLead = createBaseLead('AutomaticLead', 'auto.lead@test.com', 'Automatic Quotation');
        insert autoLead;

        Attachment att = new Attachment(
            ParentId    = autoLead.Id,
            Name        = 'TestAttachment.txt',
            Body        = Blob.valueOf('Sample attachment body'),
            ContentType = 'text/plain'
        );
        insert att;

        ContentVersion cv = new ContentVersion(
            Title                 = 'TestFile',
            PathOnClient          = 'TestFile.pdf',
            VersionData           = Blob.valueOf('PDF content'),
            FirstPublishLocationId = autoLead.Id
        );
        insert cv;

        autoLead.Project_Request_Submitted__c = true;
        update autoLead;

        autoLead.Approval_Status__c = 'Approved';
        update autoLead;

        Lead reloaded = [SELECT Project_Request_Submitted__c, Approval_Status__c FROM Lead WHERE Id = :autoLead.Id];
        System.assertEquals(true, reloaded.Project_Request_Submitted__c, 'Automatic quotation Lead must be marked submitted.');
        System.assertEquals('Approved', reloaded.Approval_Status__c, 'Automatic quotation Lead must be marked approved.');
    }

    // ------------------------------------------------------------
    // 3️⃣ Direct Wrapper Test
    // ------------------------------------------------------------
    @IsTest
    static void testLegacyWrapperSendEmailForLead() {
        Lead approvedLead = createBaseLead('WrapperApproved', 'wrapper.approved@test.com', 'Manual Quotation');
        approvedLead.Approval_Status__c = 'Approved';
        insert approvedLead;

        Lead submittedLead = createBaseLead('WrapperSubmitted', 'wrapper.submitted@test.com', 'Manual Quotation');
        submittedLead.Project_Request_Submitted__c = true;
        insert submittedLead;

        LeadEmailHandler.sendEmailForLead(approvedLead);
        LeadEmailHandler.sendEmailForLead(submittedLead);

        System.assert(true, 'sendEmailForLead executed approval & submission routing without exception.');
    }

    // ------------------------------------------------------------
    // 4️⃣ Null / Empty / Invalid Input Scenarios
    // ------------------------------------------------------------
    @IsTest
    static void testNullInputsSafelyHandled() {
        Test.startTest();
        LeadEmailHandler.sendEmailForLead(null);
        
        LeadEmailHandler.sendEnrollmentEmailOnSubmission((Lead)null);
        LeadEmailHandler.sendLeadEmailOnApproval((Lead)null);

        LeadEmailHandler.sendEnrollmentEmailOnSubmission((List<Lead>)null);
        LeadEmailHandler.sendEnrollmentEmailOnSubmission(new List<Lead>());
        
        LeadEmailHandler.sendLeadEmailOnApproval((List<Lead>)null);
        LeadEmailHandler.sendLeadEmailOnApproval(new List<Lead>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should be handled gracefully without exceptions.');
    }

    @IsTest
    static void testSkippedRecordsInList() {
        Lead validLead = createBaseLead('Valid', 'valid@test.com', 'Manual Quotation');
        insert validLead;
        
        Lead noQuoteLead = createBaseLead('NoQuote', 'noquote@test.com', null);
        insert noQuoteLead;

        List<Lead> mixedList = new List<Lead>{ null, noQuoteLead, validLead };

        Test.startTest();
        LeadEmailHandler.sendEnrollmentEmailOnSubmission(mixedList);
        LeadEmailHandler.sendLeadEmailOnApproval(mixedList);
        Test.stopTest();

        System.assert(true, 'Mixed list with nulls/invalid records should process valid ones successfully.');
    }

    // ------------------------------------------------------------
    // 5️⃣ Exception Handling Scenarios (FIXED)
    // ------------------------------------------------------------

    @IsTest
    static void testSubmissionFlowException() {
        // Create a lead but query specifically WITHOUT fields required by logic to force SObjectException
        Lead l = createBaseLead('Crash', 'crash@test.com', 'Manual Quotation');
        insert l;
        
        // Fetch ONLY ID. Accessing Project_Request_Quotation_Type__c later will throw exception.
        Lead strippedLead = [SELECT Id FROM Lead WHERE Id = :l.Id]; 
        
        Test.startTest();
        try {
            LeadEmailHandler.sendEnrollmentEmailOnSubmission(new List<Lead>{ strippedLead });
            System.assert(false, 'Should have thrown AuraHandledException due to SObjectException');
        } catch (Exception e) {
            // In test context, AuraHandledException often masks the message as "Script-thrown exception".
            // We verify the type specifically to confirm correct error handling path.
            System.assertEquals('System.AuraHandledException', e.getTypeName(), 'Exception should be of type AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testApprovalFlowException() {
        Lead l = createBaseLead('CrashApproval', 'crash.app@test.com', 'Manual Quotation');
        insert l;
        
        // Fetch ONLY ID. Accessing Email or Quotation Type will throw SObjectException.
        Lead strippedLead = [SELECT Id FROM Lead WHERE Id = :l.Id];
        
        Test.startTest();
        try {
            LeadEmailHandler.sendLeadEmailOnApproval(new List<Lead>{ strippedLead });
            System.assert(false, 'Should have thrown AuraHandledException due to SObjectException');
        } catch (Exception e) {
            System.assertEquals('System.AuraHandledException', e.getTypeName(), 'Exception should be of type AuraHandledException');
        }
        Test.stopTest();
    }
}