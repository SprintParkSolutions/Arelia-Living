/**
 * @File Name         : ContentDocumentLinkTriggerTest.cls
 * @Description       : Unit tests for ContentDocumentLink trigger / handler.
 * @Author            : 
 * @Last Modified By  : 
 * @Last Modified On  : 
 * @Modification Log  :
 * =============================================================================
 * Ver   | Date       | Author   | Modification
 * =============================================================================
 * 1.0   |            |          | Initial Version
 * =============================================================================
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class ContentDocumentLinkTriggerTest {

    /**
     * @description
     *  Helper to get a valid ContentDocumentId WITHOUT any SOQL
     *  in this test class. We:
     *    1) Create a ContentVersion via TestDataUtility
     *    2) Create a temp Account via TestDataUtility
     *    3) Use TestDataUtility.linkFileToRecord(...) which already
     *       does the SOQL on ContentVersion and gives us a CDL
     *    4) Grab ContentDocumentId from that CDL and delete the temp link
     */
    private static Id getContentDocumentIdFromUtility() {
        // Step 1: Create file
        ContentVersion cv = TestDataUtility.createContentVersion('Test File', 'dummy data');

        // Step 2: Create a temporary Account
        Account tempAcc = TestDataUtility.createAccount('Temp Link Account');

        // Step 3: Link file to temp Account (utility handles the SOQL)
        ContentDocumentLink tempCdl = TestDataUtility.linkFileToRecord(cv.Id, tempAcc.Id);

        // Step 4: Use the ContentDocumentId from that link, then clean up the temp link
        Id contentDocId = tempCdl.ContentDocumentId;
        delete tempCdl;

        return contentDocId;
    }

    /**
     * @description
     *  When a ContentDocumentLink is inserted and
     *  LinkedEntityId is Interior_Design__c:
     *   - ShareType must be updated to 'V'
     *   - Visibility must be updated to 'AllUsers'.
     */
    @IsTest
    static void testCdlUpdatedForInteriorDesign() {
        // 1) Create Interior_Design__c record
        Interior_Design__c design = new Interior_Design__c(
            Name = 'Test Interior Design'
        );
        insert design;

        // 2) Get ContentDocumentId via utility (no SOQL here)
        Id contentDocId = getContentDocumentIdFromUtility();

        // 3) Insert ContentDocumentLink (this will fire the trigger)
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId    = design.Id,
            ContentDocumentId = contentDocId,
            ShareType         = 'I',             // initial value
            Visibility        = 'InternalUsers'  // initial value
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        // 4) Verify it was updated by the handler
        ContentDocumentLink updated = [
            SELECT Id, ShareType, Visibility, LinkedEntityId
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        System.assertEquals(
            'V',
            updated.ShareType,
            'ShareType should be updated to V for Interior_Design__c files.'
        );
        System.assertEquals(
            'AllUsers',
            updated.Visibility,
            'Visibility should be updated to AllUsers for Interior_Design__c files.'
        );
        System.assertEquals(
            design.Id,
            updated.LinkedEntityId,
            'LinkedEntityId should still point to the Interior_Design__c record.'
        );
    }

    /**
     * @description
     *  When LinkedEntityId is NOT Interior_Design__c (e.g., Account),
     *  the trigger must NOT change ShareType or Visibility.
     */
    @IsTest
    static void testCdlNotUpdatedForOtherObjects() {
        // 1) Create a non-Interior_Design__c record (Account) using utility
        Account acc = TestDataUtility.createAccount('Test Account');

        // 2) Get ContentDocumentId via utility (no SOQL here)
        Id contentDocId = getContentDocumentIdFromUtility();

        // 3) Insert ContentDocumentLink with initial values
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId    = acc.Id,
            ContentDocumentId = contentDocId,
            ShareType         = 'I',
            Visibility        = 'InternalUsers'
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        // 4) Verify it was NOT modified by the handler
        ContentDocumentLink updated = [
            SELECT Id, ShareType, Visibility, LinkedEntityId
            FROM ContentDocumentLink
            WHERE Id = :cdl.Id
            LIMIT 1
        ];

        System.assertEquals(
            'I',
            updated.ShareType,
            'ShareType should NOT be changed for non-Interior_Design__c records.'
        );
        System.assertEquals(
            'InternalUsers',
            updated.Visibility,
            'Visibility should NOT be changed for non-Interior_Design__c records.'
        );
        System.assertEquals(
            acc.Id,
            updated.LinkedEntityId,
            'LinkedEntityId should still point to the Account record.'
        );
    }
}
