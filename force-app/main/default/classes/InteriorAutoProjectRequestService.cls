/**
* @File Name      : InteriorAutoProjectRequestService.cls
* @Description    : Service layer for handling Interior Project Requests from LWC,
*                   writing everything to Lead and related child records.
* PMD / Best Practices Notes:
* - No SOQL/DML inside loops.
* - No System.debug statements.
* - Public API is a single, focused entry point: saveRequest.
* - All helper methods are private and side-effect free except where clearly noted.
* @Author         :
* @Last Modified By:
* @Last Modified On: December 4, 2025
* @Modification Log:
*==============================================================================
* Ver | Date           | Author      | Modification
*==============================================================================
* 1.0 | Nov 4, 2025    |            | Initial Version (request object)
* 2.0 | Dec 4, 2025    |            | Refactored to use Lead + your fields
**/
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class InteriorAutoProjectRequestService {

    /* ==========================================================
       DTOs for existing request (used to pre-populate wizard)
       ========================================================== */

    public class ExistingRequestDTO {
        @AuraEnabled public List<RoomLineDTO>       rooms;
        @AuraEnabled public List<RoomDesignLineDTO> roomDesigns;
    }

    public class RoomLineDTO {
        @AuraEnabled public Id      roomId;
        @AuraEnabled public Integer quantity;
    }

    public class RoomDesignLineDTO {
        @AuraEnabled public Id      roomId;
        @AuraEnabled public Id      designId;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal lineAmount;
    }

    /* ==========================================================
       Public entry points
       ========================================================== */

    /**
     * @description Entry point for LWC request submission.
     *              Expects a normalized payload map from the client.
     *              Writes all data to Lead and child objects related to Lead.
     *
     * Expected keys in req:
     * - leadId (mandatory)
     * - firstName, lastName, email, phone
     * - company
     * - address  (mapped to Lead.Site_Location__c)
     * - siteSpace
     * - description (mapped to Lead.Project_Description__c)
     * - projectTypeId, categoryId, planLevel
     * - quotationType (mapped to Lead.Project_Request_Quotation_Type__c)
     * - totalBudget
     * - rooms (List<Object> with {roomId, quantity})
     * - selectedRoomDesigns (List<Object> with {roomId, designId, quantity, lineAmount})
     *
     * @return Lead Id (updated Lead).
     */

    @AuraEnabled(cacheable=false)
    public static Id saveRequest(Map<String, Object> req) {
        if (req == null) {
            throw new AuraHandledException('Empty payload');
        }

        Map<String, Object> top = normalizePayload(req);

        // Lead Id is mandatory
        String leadIdStr = getStr(top, 'leadId');
        if (String.isBlank(leadIdStr)) {
            throw new AuraHandledException('Missing Lead Id for project request.');
        }
        Id leadId = (Id) leadIdStr;

        // ---- prevent second submission ----
        Lead existingLead = [
            SELECT Id, Project_Request_Submitted__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (existingLead.Project_Request_Submitted__c == true) {
            // This message will go back to LWC & show in toast
            throw new AuraHandledException(
                'Lead details already submitted. If you have any queries, please contact Arelia Team.'
            );
        }
        // ----------------------------------------

        // Basic values
        String firstName     = getStr(top, 'firstName');
        String lastName      = getStr(top, 'lastName');
        String email         = getStr(top, 'email');
        String phone         = getStr(top, 'phone');
        String company       = getStr(top, 'company');
        String address       = getStr(top, 'address');      // -> Site_Location__c
        String siteSpace     = getStr(top, 'siteSpace');    // -> Site_Space__c
        String description   = getStr(top, 'description');  // -> Project_Description__c
        String projectTypeId = getStr(top, 'projectTypeId');
        String categoryId    = getStr(top, 'categoryId');
        String planLevel     = getStr(top, 'planLevel');
        Decimal totalBudget  = getDec(top, 'totalBudget');
        String quotationType = getStr(top, 'quotationType');

        List<Object> roomsRaw       = getList(top, 'rooms');
        List<Object> roomDesignsRaw = getList(top, 'selectedRoomDesigns');

        // 1) Update Lead with all details using YOUR fields
        Lead leadToUpdate = buildLeadUpdate(leadId,firstName,lastName,email,phone,company,address,siteSpace,
            description,totalBudget,projectTypeId,categoryId,planLevel,quotationType);

        // mark as submitted
        leadToUpdate.Project_Request_Submitted__c = true;

        update leadToUpdate;

        // 2) Rebuild child records
        deleteExistingChildRecords(leadId);

        Map<Id, String> roomNameById = new Map<Id, String>();
        if (roomsRaw != null && !roomsRaw.isEmpty()) {
            roomNameById = upsertRooms(leadId, roomsRaw);
        }

        Set<Id> designIds = new Set<Id>();
        if (roomDesignsRaw != null && !roomDesignsRaw.isEmpty()) {
            designIds = upsertRoomDesigns(leadId, roomDesignsRaw);
        }

        // 3) Attach design files to Lead
        if (!designIds.isEmpty()) {
            copyDesignFilesToLead(leadId, designIds);
        }

        return leadId;
    }

    /**
     * @description Returns Lead details needed to pre-populate the
     *              Automatic Project Request screen in LWC.
     */
    @AuraEnabled(cacheable=true)
    public static Lead fetchLeadForAutoRequest(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required to load project request details.');
        }

        // PMD-friendly CRUD guard
        if (!Schema.sObjectType.Lead.isAccessible()) {
            throw new AuraHandledException('You do not have permission to access Lead records.');
        }

        List<Lead> leads = [SELECT  Id,FirstName,LastName,Email,Phone,Company,Site_Location__c,Site_Space__c,
                    Project_Description__c,Estimated_Budget__c,Plan_Level__c,Interior_Project_Type__c,
                    Interior_Category__c,Project_Request_Quotation_Type__c FROM Lead
                    WHERE Id = :leadId LIMIT 1];

        return leads.isEmpty() ? null : leads[0];
    }

    /**
     * @description Returns existing Interior_Request_Room__c and
     *              Interior_Request_Room_Design__c records for a Lead.
     *              This lets the LWC show previously selected rooms
     *              and designs when the customer opens the page again.
     */
    @AuraEnabled(cacheable=true)
    public static ExistingRequestDTO fetchExistingRequest(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required to load existing request.');
        }

        ExistingRequestDTO dto = new ExistingRequestDTO();
        dto.rooms       = new List<RoomLineDTO>();
        dto.roomDesigns = new List<RoomDesignLineDTO>();

        // Existing rooms
        for (Interior_Request_Room__c rr : [SELECT Interior_Room__c, Quantity__c FROM Interior_Request_Room__c
                                            WHERE Lead__c = :leadId]) 
        {
            RoomLineDTO r = new RoomLineDTO();
            r.roomId   = rr.Interior_Room__c;
            r.quantity = rr.Quantity__c != null ? Integer.valueOf(String.valueOf(rr.Quantity__c)) : 0;
            dto.rooms.add(r);
        }

        // Existing room designs
        for (Interior_Request_Room_Design__c dr : [SELECT Interior_Room__c,Interior_Design__c,Quantity__c,Design_Amount__c
                                                    FROM Interior_Request_Room_Design__c WHERE Lead__c = :leadId]) 
        {
            RoomDesignLineDTO d = new RoomDesignLineDTO();
            d.roomId     = dr.Interior_Room__c;
            d.designId   = dr.Interior_Design__c;
            d.quantity   = dr.Quantity__c != null ? Integer.valueOf(String.valueOf(dr.Quantity__c)) : 0;
            d.lineAmount = dr.Design_Amount__c;
            dto.roomDesigns.add(d);
        }

        return dto;
    }

    /* ==========================================================
       Lead core helpers
       ========================================================== */

    /**
     * Uses ONLY your fields:
     * - Standard: FirstName, LastName, Email, Phone, Company
     * - Custom:   Site_Location__c, Site_Space__c,
     *             Project_Description__c,
     *             Project_Request_Quotation_Type__c,
     *             Estimated_Budget__c, Plan_Level__c,
     *             Interior_Project_Type__c, Interior_Category__c
     */
    private static Lead buildLeadUpdate(Id leadId,String firstName,String lastName,String email,String phone,
                String company,String address,String siteSpace,String description,Decimal totalBudget,
                String projectTypeId,String categoryId,String planLevel,String quotationType) 
    {
        Lead ld = new Lead();
        ld.Id = leadId;

        // Standard fields
        ld.FirstName = firstName;
        ld.LastName  = lastName;
        ld.Email     = email;
        ld.Phone     = phone;
        ld.Company   = company;

        // Your custom fields / mappings
        ld.Site_Location__c                  = address;
        ld.Site_Space__c                     = siteSpace;
        ld.Project_Description__c            = description;
        ld.Estimated_Budget__c               = totalBudget;
        ld.Plan_Level__c                     = planLevel;
        ld.Project_Request_Quotation_Type__c = quotationType;

        if (String.isNotBlank(projectTypeId)) {
            ld.Interior_Project_Type__c = (Id) projectTypeId;
        }
        if (String.isNotBlank(categoryId)) {
            ld.Interior_Category__c = (Id) categoryId;
        }

        return ld;
    }

    /**
     * Deletes existing child records related to this Lead.
     * Assumes lookup fields: Lead__c on both child objects.
     */
    private static void deleteExistingChildRecords(Id leadId) {
        if (leadId == null) {
            return;
        }

        List<Interior_Request_Room_Design__c> existingDesigns = [SELECT Id FROM Interior_Request_Room_Design__c
                                                                WHERE Lead__c = :leadId];

        List<Interior_Request_Room__c> existingRooms = [SELECT Id FROM Interior_Request_Room__c
                                                        WHERE Lead__c = :leadId];

        if (!existingDesigns.isEmpty()) {
            delete existingDesigns;
        }
        if (!existingRooms.isEmpty()) {
            delete existingRooms;
        }
    }

    /* ==========================================================
       Child records (Rooms + Designs)
       ========================================================== */

    private static Map<Id, String> upsertRooms(Id leadId, List<Object> roomsRaw) {
        Set<Id> roomIds = collectIds(roomsRaw, 'roomId');
        Map<Id, String> roomNameById = roomIds.isEmpty()
            ? new Map<Id, String>()
            : loadRoomNames(roomIds);

        List<Interior_Request_Room__c> toInsert = new List<Interior_Request_Room__c>();
        for (Object o : roomsRaw) {
            Map<String, Object> r = normalizePayload(o);
            String roomIdStr = getStr(r, 'roomId');
            if (String.isBlank(roomIdStr)) {
                continue;
            }

            Integer qty = getInt(r, 'quantity', 1);
            toInsert.add(new Interior_Request_Room__c(
                Lead__c          = leadId,
                Interior_Room__c = (Id) roomIdStr,
                Quantity__c      = qty
            ));
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        return roomNameById;
    }

    private static Map<Id, String> loadRoomNames(Set<Id> roomIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (roomIds == null || roomIds.isEmpty()) {
            return out;
        }

        for (Interior_Room__c rr : [SELECT Id, Name FROM Interior_Room__c WHERE Id IN :roomIds]) {
            out.put(rr.Id, rr.Name);
        }
        return out;
    }

    private static Set<Id> upsertRoomDesigns(Id leadId, List<Object> roomDesignsRaw) {
        List<Interior_Request_Room_Design__c> toInsert = new List<Interior_Request_Room_Design__c>();
        Set<Id> designIds = new Set<Id>();

        for (Object o : roomDesignsRaw) {
            Map<String, Object> m = normalizePayload(o);
            String roomIdStr   = getStr(m, 'roomId');
            String designIdStr = getStr(m, 'designId');
            Integer qty        = getInt(m, 'quantity', 1);
            Decimal lineAmt    = getDec(m, 'lineAmount');

            if (String.isNotBlank(designIdStr)) {
                designIds.add((Id) designIdStr);
            }

            toInsert.add(new Interior_Request_Room_Design__c(
                Lead__c            = leadId,
                Interior_Room__c   = String.isNotBlank(roomIdStr)   ? (Id) roomIdStr   : null,
                Interior_Design__c = String.isNotBlank(designIdStr) ? (Id) designIdStr : null,
                Quantity__c        = qty,
                Design_Amount__c   = lineAmt
            ));
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        return designIds;
    }

    private static void copyDesignFilesToLead(Id leadId, Set<Id> designIds) {
        if (leadId == null || designIds == null || designIds.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> links = [SELECT ContentDocumentId, LinkedEntityId
                                    FROM ContentDocumentLink WHERE LinkedEntityId IN :designIds];
        if (links.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink dl : links) {
            newLinks.add(new ContentDocumentLink(
                LinkedEntityId    = leadId,
                ContentDocumentId = dl.ContentDocumentId
                //, ShareType         = 'V',
                // Visibility        = 'AllUsers'
            ));
        }

        if (!newLinks.isEmpty()) {
            insert newLinks;
        }
    }

    /* ==========================================================
       JSON / utility helpers
       ========================================================== */

    private static Map<String, Object> normalizePayload(Object anyObj) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(anyObj));
    }

    private static String getStr(Map<String, Object> m, String key) {
        if (m == null || String.isBlank(key)) {
            return null;
        }
        Object val = m.get(key);
        return (val == null) ? null : String.valueOf(val);
    }

    private static Decimal getDec(Map<String, Object> m, String key) {
        if (m == null || String.isBlank(key)) {
            return null;
        }
        Object val = m.get(key);
        if (val == null) {
            return null;
        }
        return Decimal.valueOf(String.valueOf(val));
    }

    private static Integer getInt(Map<String, Object> m, String key, Integer dft) {
        if (m == null || String.isBlank(key)) {
            return dft;
        }
        Object val = m.get(key);
        if (val == null) {
            return dft;
        }
        return Integer.valueOf(String.valueOf(val));
    }

    private static List<Object> getList(Map<String, Object> m, String key) {
        if (m == null || String.isBlank(key)) {
            return new List<Object>();
        }
        Object val = m.get(key);
        return (val == null)
            ? new List<Object>()
            : (List<Object>) JSON.deserializeUntyped(JSON.serialize(val));
    }

    private static Set<Id> collectIds(List<Object> rows, String idFieldKey) {
        Set<Id> out = new Set<Id>();
        if (rows == null || rows.isEmpty() || String.isBlank(idFieldKey)) {
            return out;
        }

        for (Object o : rows) {
            Map<String, Object> r = normalizePayload(o);
            String idStr = getStr(r, idFieldKey);
            if (String.isNotBlank(idStr)) {
                out.add((Id) idStr);
            }
        }
        return out;
    }

    private static Boolean isEmpty(List<String> lst) {
        return (lst == null || lst.isEmpty());
    }

    private static String nvl(String s) {
        return (s == null) ? 'Not specified' : s;
    }

    private static String formatAmount(Decimal amt) {
        if (amt == null) {
            return '';
        }
        String s = String.valueOf(amt.setScale(2));
        List<String> parts = s.split('\\.');
        String intPart = parts[0];
        String decPart = parts.size() > 1 ? parts[1] : '00';

        String formattedInt = '';
        Integer count = 0;

        for (Integer i = intPart.length() - 1; i >= 0; i--) {
            formattedInt = intPart.substring(i, i + 1) + formattedInt;
            count++;
            if (count == 3 && i > 0) {
                formattedInt = ',' + formattedInt;
                count = 0;
            }
        }
        return formattedInt + '.' + decPart;
    }
}
