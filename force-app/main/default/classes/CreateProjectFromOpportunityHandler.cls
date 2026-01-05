/* File: CreateProjectFromOpportunityHandler.cls
   @Description:
     When an Opportunity moves to Closed Won:
       - If a related Project__c (keyed by Project_Name__c = Opp.Id) exists → UPDATE it from Opp values
       - If not → CREATE it from Opp values and copy files from Opp to Project

     Gates (adds addError on the Opportunity row if any fail):
       - Client_Agreement_Signed__c = true
       - All_Vendors_Agreement_Completed__c = true
       - All Vendor_Opportunity__c.Vendor_Agreement_Signed__c = true

   Notes:
     - Bulk safe, low cognitive complexity, null-safe booleans.
*/

public without sharing class CreateProjectFromOpportunityHandler {

    // ---------- Orchestrator ----------
    public static void handleAfterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        // 1) Only Opps that just moved to Closed Won
        List<Opportunity> justClosedWon = pickJustClosedWon(newList, oldMap);
        if (justClosedWon.isEmpty()) return;

        // 2) Load vendor links for those Opps (for validation)
        Set<Id> oppIds = collectIds(justClosedWon);
        Map<Id, List<Vendor_Opportunity__c>> vendorsByOpp = loadVendorLinks(oppIds);

        // 3) Validate gates; invalid rows receive addError and are excluded
        List<Opportunity> validOpps = validateAndFilter(justClosedWon, vendorsByOpp);
        if (validOpps.isEmpty()) return;

        // 4) Find existing projects keyed by Project_Name__c = Opportunity.Id
        Map<Id, Project__c> existingByOppId = loadExistingProjectsByOppId(collectIds(validOpps));

        // 5) Build create/update lists
        List<Project__c> toInsert = new List<Project__c>();
        List<Project__c> toUpdate = new List<Project__c>();
        for (Opportunity opp : validOpps) {
            Project__c existing = existingByOppId.get(opp.Id);
            if (existing == null) {
                toInsert.add(buildProjectFromOpp(opp, null));
            } else {
                toUpdate.add(buildProjectFromOpp(opp, existing.Id));
            }
        }

        // 6) DML (update first or insert first — order does not matter functionally)
        if (!toUpdate.isEmpty()) update toUpdate;

        Map<Id, Id> oppToNewProject = new Map<Id, Id>();
        if (!toInsert.isEmpty()) {
            insert toInsert;
            // Map inserted projects back to Opps for file copy
            for (Project__c p : toInsert) {
                if (p.Project_Name__c != null) oppToNewProject.put(p.Project_Name__c, p.Id);
            }
        }

        // 7) Copy files only for newly created projects (unchanged behavior)
        if (!oppToNewProject.isEmpty()) copyFilesFromOppToProject(oppToNewProject);
    }

    // ---------- Step 1: find Opps that just moved to Closed Won ----------
    private static List<Opportunity> pickJustClosedWon(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Opportunity> result = new List<Opportunity>();
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            Boolean nowClosedWon = 'Closed Won'.equals(opp.StageName);
            Boolean wasClosedWon = (oldOpp != null && 'Closed Won'.equals(oldOpp.StageName));
            if (nowClosedWon && !wasClosedWon) {
                result.add(opp);
            }
        }
        return result;
    }

    private static Set<Id> collectIds(List<Opportunity> opps) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity o : opps) ids.add(o.Id);
        return ids;
    }

    // ---------- Step 2: fetch vendors per Opp ----------
    private static Map<Id, List<Vendor_Opportunity__c>> loadVendorLinks(Set<Id> oppIds) {
        Map<Id, List<Vendor_Opportunity__c>> mapByOpp = new Map<Id, List<Vendor_Opportunity__c>>();
        if (oppIds == null || oppIds.isEmpty()) return mapByOpp;

        for (Vendor_Opportunity__c vo : [
            SELECT Id, Opportunity__c,
                   Vendor__c, Vendor__r.Name,
                   Vendor_Agreement_Sent__c, Vendor_Agreement_Signed__c
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c IN :oppIds
        ]) {
            List<Vendor_Opportunity__c> bucket = mapByOpp.get(vo.Opportunity__c);
            if (bucket == null) {
                bucket = new List<Vendor_Opportunity__c>();
                mapByOpp.put(vo.Opportunity__c, bucket);
            }
            bucket.add(vo);
        }
        return mapByOpp;
    }

    // ---------- Step 3: validations (addError on the Opportunity row) ----------
    private static List<Opportunity> validateAndFilter(
        List<Opportunity> candidates,
        Map<Id, List<Vendor_Opportunity__c>> vendorsByOpp
    ) {
        List<Opportunity> valids = new List<Opportunity>();
        for (Opportunity opp : candidates) {
            List<String> errs = new List<String>();
            validateClientAgreement(opp, errs);
            validateAllVendorsCompleted(opp, errs);
            validateVendorsSigned(opp, vendorsByOpp.get(opp.Id), errs);

            if (!errs.isEmpty()) {
                opp.addError('Cannot create/update Project: ' + String.join(errs, ' '));
            } else {
                valids.add(opp);
            }
        }
        return valids;
    }

    private static void validateClientAgreement(Opportunity opp, List<String> errs) {
        if (opp.Client_Agreement_Signed__c != true) {
            errs.add('Client Agreement is not signed on Opportunity.');
        }
    }

    private static void validateAllVendorsCompleted(Opportunity opp, List<String> errs) {
        if (opp.All_Vendors_Agreement_Completed__c != true) {
            errs.add('All Vendors Agreement not completed. Please check.');
        }
    }

    private static void validateVendorsSigned(Opportunity opp, List<Vendor_Opportunity__c> links, List<String> errs) {
        if (links == null || links.isEmpty()) {
            errs.add('No Vendor_Opportunity__c records linked to this Opportunity.');
            return;
        }
        List<String> missing = new List<String>();
        for (Vendor_Opportunity__c vo : links) {
            if (vo.Vendor_Agreement_Signed__c != true) {
                String nameOrId = (vo.Vendor__r != null && String.isNotBlank(vo.Vendor__r.Name))
                    ? vo.Vendor__r.Name : (String) vo.Vendor__c;
                missing.add(nameOrId);
            }
        }
        if (!missing.isEmpty()) {
            errs.add('These vendor(s) have not signed the agreement: ' + String.join(missing, ', ') + '.');
        }
    }

    // ---------- Step 4: load existing Projects keyed by Opp.Id ----------
    private static Map<Id, Project__c> loadExistingProjectsByOppId(Set<Id> oppIds) {
        Map<Id, Project__c> out = new Map<Id, Project__c>();
        if (oppIds == null || oppIds.isEmpty()) return out;

        for (Project__c p : [
            SELECT Id, Project_Name__c
            FROM Project__c
            WHERE Project_Name__c IN :oppIds
        ]) {
            if (p.Project_Name__c != null) out.put((Id) p.Project_Name__c, p);
        }
        return out;
    }

    // ---------- Step 5: build a Project row for INSERT or UPDATE ----------
    // Pass existingId = null for INSERT, or existing Project Id for UPDATE
    private static Project__c buildProjectFromOpp(Opportunity opp, Id existingId) {
        // Re-visit override logic
        final Boolean isRevisitConfirmed =
            'Re-Visit'.equalsIgnoreCase(opp.Appointment_Status__c) &&
            (opp.Re_Visit_Appointmnet_Confirmation__c == true);

        final Date endDateVal = isRevisitConfirmed
            ? opp.Re_Visit_Site_Supervisor_Completion_Date__c
            : opp.Project_End_Date__c;

        final Decimal estBudgetVal = isRevisitConfirmed
            ? opp.Re_Visit_Site_Supervisor_Estimate_Budget__c
            : opp.Supervisor_Estimated_Budget__c;

        Project__c p = new Project__c(
            Id                              = existingId,          // null for insert; non-null for update
            Description__c                  = opp.Project_Description__c,
            Budget__c                       = opp.Budget__c,
            Status__c                       = 'Initiated',
            IDC_Company__c                  = opp.AccountId,
            Client__c                       = opp.Primary_Contact__c,
            Project_Name__c                 = opp.Id,              // key back to Opportunity
            Client_Email__c                 = opp.Email__c,
            Name                            = opp.Name,
            Client_Phone__c                 = opp.Lead_Phone__c,
            Supervisor_User__c              = opp.Supervisor_User__c,
            Type_Of_Project__c              = opp.Type_of_Project__c,
            Project_Scope__c                = opp.Project_Scope__c,
            End_Date__c                     = endDateVal,
            Supervisor_Estimated_Budget__c  = estBudgetVal,
            // 🔹 NEW FIELD MAPPINGS 🔹
            Project_Request_Quotation_Type__c = opp.Project_Request_Quotation_Type__c,
            Site_Location__c                  = opp.Site_Location__c,
            Site_Space__c                     = opp.Site_Space__c,
            Plan_Level__c                     = opp.Plan_Level__c
        );
        return p;
    }

    // ---------- Step 6: file copy (only for newly created Projects) ----------
    private static void copyFilesFromOppToProject(Map<Id, Id> oppToProject) {
        if (oppToProject == null || oppToProject.isEmpty()) return;

        List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :oppToProject.keySet()
        ]) {
            Id projectId = oppToProject.get(link.LinkedEntityId);
            if (projectId == null) continue;

            toInsert.add(new ContentDocumentLink(
                ContentDocumentId = link.ContentDocumentId,
                LinkedEntityId    = projectId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }
}