/**
 * Handles customer approval & reschedule from Experience Cloud page (for Opportunity).
 * Opportunity fields:
 *  - Re_Visit_Appointment_Date__c (Date)
 *  - Re_Visit_Appointment_Time_Slots__c (Text/Picklist)
 *  - Re_Visit_Appointment_Rescheduled_Date__c (Date)
 *  - Re_Visit_Appointm_Rescheduled_Time_Slots__c (Text/Picklist)
 *  - Re_Visit_Site_Appointment_Status__c (Picklist: Pending, Approved, Rescheduled)
 *  - Supervisor_User__c (Lookup(User))
 *
 * Lead fields:
 *  - Appointment_Date__c (Date)
 *  - Appointment_Time_Slots__c (Text/Picklist)
 *  - Appointment_Rescheduled_Time__c (Date)   // rescheduled DATE
 *  - Time_Slots__c (Text/Picklist)            // rescheduled SLOT
 *  - Appointment_Status__c (Picklist: Pending, Approved, Rescheduled)
 *  - Supervisor_User__c (Lookup(User))
 *
 * EmailTemplates:
 *  - Opportunity_Appointment_Approved_Email
 *  - Opportunity_Appointment_Rescheduled_Email
 *
 * Label:
 *  - Arelia_OWD (Org-Wide Email Address)
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class AppointmentControllerToOpp {

    // ---- Lead reschedule pair (matches your org)
    private static final String LEAD_RESCHED_DATE_FIELD = 'Appointment_Rescheduled_Time__c';
    private static final String LEAD_RESCHED_SLOT_FIELD = 'Time_Slots__c';

    // ===== Null-safe helpers =====
    private static String toStringOrEmpty(String v) { return v == null ? '' : v; }
    private static String dateToStringOrEmpty(Date d) { return d == null ? '' : String.valueOf(d); } // yyyy-MM-dd

    // ===== Public: update status =====
    @AuraEnabled
    public static void updateAppointmentStatus(
        Id opportunityId,
        String status,
        String rejectionReason,
        Date rescheduleDate,
        String timeSlot
    ) {
        if (String.isBlank(opportunityId)) {
            throw new AuraHandledException('Opportunity ID is missing.');
        }
        if (String.isBlank(status)) {
            throw new AuraHandledException('Status is required.');
        }

// Locate this block in AppointmentControllerToOpp.cls
        Opportunity opp = [
            SELECT Id, Name,
                Re_Visit_Site_Appointment_Status__c,
                Primary_Contact__c, 
                Primary_Contact__r.Name, 
                Primary_Contact__r.Phone, 
                Primary_Contact__r.Email,
                Re_Visit_Appointment_Date__c, 
                Re_Visit_Appointment_Time_Slots__c,
                Re_Visit_Appointment_Rescheduled_Date__c, 
                Re_Visit_Appointm_Rescheduled_Time_Slots__c,
                Supervisor_User__c, 
                Supervisor_User__r.FirstName,
                Supervisor_User__r.LastName,
                Supervisor_User__r.Phone, 
                Supervisor_User__r.Email
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        // Allow responses only while still Pending or Rescheduled
        String existing = opp.Re_Visit_Site_Appointment_Status__c;
        if (String.isNotBlank(existing) && existing != 'Pending' && existing != 'Rescheduled') {
            throw new AuraHandledException('Your response was already submitted as ' + existing + '. Further changes are not allowed.');
        }

        if ('Approved'.equalsIgnoreCase(status)) {
            opp.Re_Visit_Site_Appointment_Status__c = 'Approved';
            opp.Re_Visit_Appointment_Rescheduled_Date__c = null;
            opp.Re_Visit_Appointm_Rescheduled_Time_Slots__c = null;
        } else if ('Rescheduled'.equalsIgnoreCase(status)) {
            if (rescheduleDate == null || String.isBlank(timeSlot)) {
                throw new AuraHandledException('Please select both a date and a time slot.');
            }

            if (!isSlotAvailableForSupervisor(opp.Supervisor_User__c, rescheduleDate, timeSlot, opp.Id)) {
                throw new AuraHandledException('That time slot is already booked for the selected date. Please choose another.');
            }

            opp.Re_Visit_Site_Appointment_Status__c = 'Rescheduled';
            opp.Re_Visit_Appointment_Date__c = null;
            opp.Re_Visit_Appointment_Time_Slots__c = null;
            opp.Re_Visit_Appointment_Rescheduled_Date__c = rescheduleDate;
            opp.Re_Visit_Appointm_Rescheduled_Time_Slots__c = timeSlot;
        } else {
            throw new AuraHandledException('Unsupported status: ' + status);
        }

        update opp;
        sendConfirmationEmail(opp, opp.Re_Visit_Site_Appointment_Status__c);
    }

    // ===== Public: available slots (excludes Lead + Opp booked slots in Pending/Approved/Rescheduled) =====
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableTimeSlots(Date forDate, Id currentOpportunityId) {
        if (forDate == null) {
            throw new AuraHandledException('Please select a date first.');
        }
        if (String.isBlank(currentOpportunityId)) {
            throw new AuraHandledException('Opportunity ID is missing.');
        }

        Opportunity currentOpp = [
            SELECT Id, Supervisor_User__c
            FROM Opportunity
            WHERE Id = :currentOpportunityId
            LIMIT 1
        ];

        // Pull from Opp reschedule picklist
        List<String> allSlots = getPicklistValues(Opportunity.Re_Visit_Appointm_Rescheduled_Time_Slots__c);
        if (allSlots.isEmpty()) {return allSlots;}

        Set<String> taken = collectTakenSlots(currentOpp.Supervisor_User__c, forDate, currentOpportunityId);

        List<String> available = new List<String>();
        for (String s : allSlots) {
            String key = s == null ? null : s.trim();
            if (String.isBlank(key)) {continue;}
            if (!taken.contains(key)) {
                available.add(s);
            }
        }
        return available;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        return getPicklistValues(Opportunity.Re_Visit_Appointm_Rescheduled_Time_Slots__c);
    }

    // ===== Private: universal availability (Lead + Opp, Pending/Approved/Rescheduled) =====
    private static Boolean isSlotAvailableForSupervisor(Id supervisorUserId, Date onDate, String slotLabel, Id excludeOpportunityId) {
        if (supervisorUserId == null || onDate == null || String.isBlank(slotLabel)) {return false;}
        Set<String> taken = collectTakenSlots(supervisorUserId, onDate, excludeOpportunityId);
        return !taken.contains(slotLabel.trim());
    }

    /**
     * Collects all taken slots for a Supervisor on a given date across:
     *  - Opportunities (initial + rescheduled) with status in (Pending, Approved, Rescheduled)
     *  - Leads         (initial + rescheduled) with status in (Pending, Approved, Rescheduled)
     * Excludes the current Opportunity by Id where appropriate.
     */
    private static Set<String> collectTakenSlots(Id supervisorId, Date forDate, Id excludeOpportunityId) {
        Set<String> taken = new Set<String>();

        // --- Opportunities: RESCHEDULED ---
        for (AggregateResult ar : [
            SELECT Re_Visit_Appointm_Rescheduled_Time_Slots__c slot
            FROM Opportunity
            WHERE Supervisor_User__c = :supervisorId
              AND Re_Visit_Site_Appointment_Status__c IN ('Pending','Approved','Rescheduled')
              AND Re_Visit_Appointment_Rescheduled_Date__c = :forDate
              AND Re_Visit_Appointm_Rescheduled_Time_Slots__c != null
              AND Id != :excludeOpportunityId
            GROUP BY Re_Visit_Appointm_Rescheduled_Time_Slots__c
        ]) {
            taken.add(((String) ar.get('slot'))?.trim());
        }

        // --- Opportunities: INITIAL ---
        for (AggregateResult ar2 : [
            SELECT Re_Visit_Appointment_Time_Slots__c slot
            FROM Opportunity
            WHERE Supervisor_User__c = :supervisorId
              AND Re_Visit_Site_Appointment_Status__c IN ('Pending','Approved','Rescheduled')
              AND Re_Visit_Appointment_Date__c = :forDate
              AND Re_Visit_Appointment_Time_Slots__c != null
              AND Id != :excludeOpportunityId
            GROUP BY Re_Visit_Appointment_Time_Slots__c
        ]) {
            taken.add(((String) ar2.get('slot'))?.trim());
        }

        // --- Leads: RESCHEDULED ---
        // Dynamic SOQL to use your exact API names above.
        String soqlLeadRes =
            'SELECT ' + LEAD_RESCHED_SLOT_FIELD + ' slot ' +
            'FROM Lead ' +
            'WHERE Supervisor_User__c = :supervisorId ' +
            'AND Appointment_Status__c IN (\'Pending\',\'Approved\',\'Rescheduled\') ' +
            'AND ' + LEAD_RESCHED_DATE_FIELD + ' = :forDate ' +
            'AND ' + LEAD_RESCHED_SLOT_FIELD + ' != null ' +
            'GROUP BY ' + LEAD_RESCHED_SLOT_FIELD;

        for (AggregateResult ar3 : Database.query(soqlLeadRes)) {
            taken.add(((String) ar3.get('slot'))?.trim());
        }

        // --- Leads: INITIAL ---
        for (AggregateResult ar4 : [
            SELECT Appointment_Time_Slots__c slot
            FROM Lead
            WHERE Supervisor_User__c = :supervisorId
              AND Appointment_Status__c IN ('Pending','Approved','Rescheduled')
              AND Appointment_Date__c = :forDate
              AND Appointment_Time_Slots__c != null
            GROUP BY Appointment_Time_Slots__c
        ]) {
            taken.add(((String) ar4.get('slot'))?.trim());
        }

        taken.remove('');
        return taken;
    }

    /** Get picklist labels for a field. */
    private static List<String> getPicklistValues(Schema.sObjectField field) {
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry pe : field.getDescribe().getPicklistValues()) {
            vals.add(pe.getLabel());
        }
        return vals;
    }

    /** Sends email to the Supervisor (User). NOTE: no WhatId allowed for User targets. */
    private static void sendConfirmationEmail(Opportunity opp, String status) {
        if (opp == null || opp.Supervisor_User__c == null) {return;}

        final String templateName = 'Approved'.equalsIgnoreCase(status)
            ? Label.Arelia_Living_Opportunity_Appointment_Approved_Email
            : Label.Arelia_Living_Opportunity_Appointment_Rescheduled_Email;

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = :templateName
            LIMIT 1
        ];
        if (tpl == null || String.isBlank(tpl.HtmlValue) || String.isBlank(tpl.Subject)) {return;}

        // 🔹 Supervisor Full Name (First + Last)
        String supervisorFullName = '';
        if (opp.Supervisor_User__r != null) {
            supervisorFullName =
                toStringOrEmpty(opp.Supervisor_User__r.FirstName) +
                (String.isNotBlank(opp.Supervisor_User__r.FirstName) &&
                 String.isNotBlank(opp.Supervisor_User__r.LastName) ? ' ' : '') +
                toStringOrEmpty(opp.Supervisor_User__r.LastName);
        }

        String subject = tpl.Subject.replace('{{{Recipient.Name}}}',
            toStringOrEmpty(opp.Primary_Contact__r != null ? opp.Primary_Contact__r.Name : null));

        String html = tpl.HtmlValue
            .replace('{{{Recipient.Name}}}', toStringOrEmpty(opp.Primary_Contact__r != null ? opp.Primary_Contact__r.Name : null))
            .replace('{{{Recipient.Phone}}}', toStringOrEmpty(opp.Primary_Contact__r != null ? opp.Primary_Contact__r.Phone : null))
        //    .replace('{{{Supervisor_User__c.Name}}}',  toStringOrEmpty(opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Name  : null))
            .replace('{{{Supervisor_User__c.Name}}}', supervisorFullName)
            .replace('{{{Supervisor_User__c.Phone}}}', toStringOrEmpty(opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Phone : null))
            .replace('{{{Supervisor_User__c.Email}}}', toStringOrEmpty(opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Email : null))
            .replace('{{{Re_Visit_Appointment_Date__c}}}',             formatDateMDY(opp.Re_Visit_Appointment_Date__c))
            .replace('{{{Re_Visit_Appointment_Time_Slots__c}}}',       toStringOrEmpty(opp.Re_Visit_Appointment_Time_Slots__c))
            .replace('{{{Re_Visit_Appointment_Rescheduled_Date__c}}}', formatDateMDY(opp.Re_Visit_Appointment_Rescheduled_Date__c))
            .replace('{{{Re_Visit_Appointm_Rescheduled_Time_Slots__c}}}', toStringOrEmpty(opp.Re_Visit_Appointm_Rescheduled_Time_Slots__c));

        if (opp.Supervisor_User__r == null || String.isBlank(opp.Supervisor_User__r.Email)) {return;}

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setSubject(subject);
        msg.setHtmlBody(html);
        msg.setTargetObjectId(opp.Supervisor_User__c);
        msg.setCcAddresses(new List<String>{ opp.Primary_Contact__r.Email });
        Id owd = getDefaultOrgWideEmailAddressId();
        if (owd != null) {msg.setOrgWideEmailAddressId(owd);}
        msg.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    /** Fetch Org-Wide Email Address by label from Custom Label Arelia_OWD. */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    private static String formatDateMDY(Date d) {
        return d == null
            ? ''
            : DateTime.newInstance(d, Time.newInstance(0,0,0,0)).format('MM/dd/yyyy');
    }
}