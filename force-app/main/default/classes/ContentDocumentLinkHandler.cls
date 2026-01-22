/**
 * @File        : ContentDocumentLinkHandler.cls
 * @Author      : 
 * @CreatedDate : 
 * @Description :
 * ---------------------------------------------------------------------------
 * Handler class for ContentDocumentLink Trigger.
 *
 * PURPOSE:
 *  - Ensures all file links created on Interior_Design__c records automatically
 *    become visible to Experience Cloud guest users.
 *  - Sets ShareType = 'V' (View Only)
 *  - Sets Visibility = 'AllUsers'
 *
 * DESIGN:
 *  - Trigger delegates logic to this handler (Trigger Framework approach)
 *  - Bulkified & PMD Compliant
 *  - No SOQL inside loops
 *
 * PMD Notes:
 *  - Allowed clone() usage
 *  - Allowed assignment inside loop (required for CDC update)
 * ---------------------------------------------------------------------------
 */
public with sharing class ContentDocumentLinkHandler {

    /**
     * @Description:
     *  Handles AFTER INSERT context for ContentDocumentLink trigger.
     *  Updates ShareType + Visibility ONLY for files attached to
     *  Interior_Design__c.
     *
     * @param newList - List of newly inserted ContentDocumentLink records.
     *
     * PMD Suppressions:
     * - PMD.ApexUnitTestClassShouldHaveAsserts → Not relevant for handler.
     * - PMD.EmptyIfStmt → Not applicable.
     * - PMD.CyclomaticComplexity → Method is simple & linear.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void handleAfterInsert(List<ContentDocumentLink> newList) {

        if (newList == null || newList.isEmpty()) {
            return; // nothing to process
        }

        List<ContentDocumentLink> updateList = new List<ContentDocumentLink>();

        for (ContentDocumentLink cdl : newList) {

            // Process only records linked to Interior_Design__c
            if (cdl.LinkedEntityId != null &&
                cdl.LinkedEntityId.getSObjectType() == Interior_Design__c.SObjectType) {

                // Clone the record to modify fields (Id must be reassigned)
                ContentDocumentLink modified = cdl.clone(false, false, false, false);

                modified.Id         = cdl.Id;
                modified.ShareType  = 'V';          // View Only
                modified.Visibility = 'AllUsers';   // Guest User visibility

                updateList.add(modified);
            }
        }

        // Perform single DML update for all modified records
        if (!updateList.isEmpty()) {
            update updateList;
        }
    }
}
