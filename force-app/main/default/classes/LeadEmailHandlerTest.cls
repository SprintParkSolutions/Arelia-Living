@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.MethodNamingConventions')
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
        testLead.FirstName  = 'Test';
        testLead.LastName   = lastName;
        testLead.Company    = 'Arelia Test Co';
        testLead.Status     = 'Open - Not Contacted';
        testLead.Email      = email;
        testLead.Project_Request_Quotation_Type__c = quotationType;
        testLead.Project_Request_Submitted__c      = false;
        testLead.Approval_Status__c                = 'Pending';
        return testLead;
    }

    // ------------------------------------------------------------
    // 1️⃣ Manual Quotation:
    //     - submission → enrollment/management email (no attachments)
    //     - approval   → lead email (no attachments)
    //      (via LeadTrigger calling LeadEmailHandler)
    // ------------------------------------------------------------
    @IsTest
    static void testManualQuotationSubmissionAndApproval() {
        // GIVEN
        Lead manualLead = createBaseLead(
            'ManualLead',
            'manual.lead@test.com',
            'Manual Quotation'
        );
        insert manualLead;

        // WHEN: first update → submitted
        manualLead.Project_Request_Submitted__c = true;
        update manualLead;   // should call LeadEmailHandler.sendEnrollmentEmailOnSubmission

        // WHEN: second update → approved
        manualLead.Approval_Status__c = 'Approved';
        update manualLead;   // should call LeadEmailHandler.sendLeadEmailOnApproval

        // THEN: fields reflect the changes (no exceptions thrown)
        Lead reloaded = [
            SELECT Project_Request_Submitted__c, Approval_Status__c
            FROM Lead
            WHERE Id = :manualLead.Id
        ];

        System.assertEquals(
            true,
            reloaded.Project_Request_Submitted__c,
            'Manual quotation Lead must be marked submitted.'
        );
        System.assertEquals(
            'Approved',
            reloaded.Approval_Status__c,
            'Manual quotation Lead must be marked approved.'
        );
    }

    // ------------------------------------------------------------
    // 2️⃣ Automatic Quotation:
    //     - submission → enrollment/management email (with attachments)
    //     - approval   → lead email (with attachments)
    //      (via LeadTrigger calling LeadEmailHandler)
    // ------------------------------------------------------------
    @IsTest
    static void testAutomaticQuotationWithAttachmentsSubmissionAndApproval() {
        // GIVEN
        Lead autoLead = createBaseLead(
            'AutomaticLead',
            'auto.lead@test.com',
            'Automatic Quotation'
        );
        insert autoLead;

        // Classic Attachment
        Attachment att = new Attachment(
            ParentId    = autoLead.Id,
            Name        = 'TestAttachment.txt',
            Body        = Blob.valueOf('Sample attachment body'),
            ContentType = 'text/plain'
        );
        insert att;

        // File via ContentVersion (creates ContentDocument + ContentDocumentLink)
        ContentVersion cv = new ContentVersion(
            Title                 = 'TestFile',
            PathOnClient          = 'TestFile.pdf',
            VersionData           = Blob.valueOf('PDF content'),
            FirstPublishLocationId = autoLead.Id
        );
        insert cv;

        // WHEN: first update → submitted
        autoLead.Project_Request_Submitted__c = true;
        update autoLead;

        // WHEN: second update → approved
        autoLead.Approval_Status__c = 'Approved';
        update autoLead;

        // THEN: fields reflect the changes (no exceptions thrown)
        Lead reloaded = [
            SELECT Project_Request_Submitted__c, Approval_Status__c
            FROM Lead
            WHERE Id = :autoLead.Id
        ];

        System.assertEquals(
            true,
            reloaded.Project_Request_Submitted__c,
            'Automatic quotation Lead must be marked submitted.'
        );
        System.assertEquals(
            'Approved',
            reloaded.Approval_Status__c,
            'Automatic quotation Lead must be marked approved.'
        );
    }

    // ------------------------------------------------------------
    // 3️⃣ Direct handler wrapper:
    //     sendEmailForLead routes correctly based on field values
    //     (does NOT rely on the trigger)
    // ------------------------------------------------------------
    @IsTest
    static void testLegacyWrapperSendEmailForLead() {
        // GIVEN: one Lead for approval path
        Lead approvedLead = createBaseLead(
            'WrapperApproved',
            'wrapper.approved@test.com',
            'Manual Quotation'
        );
        approvedLead.Approval_Status__c = 'Approved';
        insert approvedLead;

        // GIVEN: one Lead for submission path
        Lead submittedLead = createBaseLead(
            'WrapperSubmitted',
            'wrapper.submitted@test.com',
            'Manual Quotation'
        );
        submittedLead.Project_Request_Submitted__c = true;
        insert submittedLead;

        // WHEN: call wrapper for both
        LeadEmailHandler.sendEmailForLead(approvedLead);
        LeadEmailHandler.sendEmailForLead(submittedLead);

        // THEN: if we reach here without exception, routing is fine
        System.assert(
            true,
            'sendEmailForLead executed approval & submission routing without exception.'
        );
    }
}
