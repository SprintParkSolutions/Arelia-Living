public without sharing class ProjectStatusController {

    /* =========================
       DTOs
    ========================== */

    public class TaskDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Date   startDate;
        @AuraEnabled public Date   dueDate;
        @AuraEnabled public Decimal assignedPercent;
        @AuraEnabled public Date   finalCompletedDate;
        @AuraEnabled public Integer numberOfDays;
    }

    public class VendorAssignmentDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String vendorName;
        @AuraEnabled public String category;
        @AuraEnabled public String status;
        @AuraEnabled public Date   workStartDate;
        @AuraEnabled public Date   workEndDate;
        @AuraEnabled public Integer workDuration;
        @AuraEnabled public Decimal amount;

        // NEW – use the field on Vendor Assignment
        @AuraEnabled public Decimal completionPercent;

        @AuraEnabled public List<TaskDTO> tasks;
    }

    public class ProjectDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Date   startDate;
        @AuraEnabled public Date   endDate;
        @AuraEnabled public String estimatedDuration;

        // NEW – use the field on Project
        @AuraEnabled public Decimal completionPercent;

        @AuraEnabled public List<VendorAssignmentDTO> vendorAssignments;
    }

    public class AuthResponseDTO {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public List<ProjectDTO> projects;
    }

    /* =========================
       PUBLIC METHOD
    ========================== */

    @AuraEnabled(cacheable=false)
    public static AuthResponseDTO loginAndFetch(String email, String password) {
        AuthResponseDTO res = new AuthResponseDTO();
        res.projects = new List<ProjectDTO>();

        if (String.isBlank(email) || String.isBlank(password)) {
            res.success = false;
            res.message = 'Please enter both Email and Password.';
            return res;
        }

        // 1) Contact
        List<Contact> matches = [
            SELECT Id, Email
            FROM Contact
            WHERE Email = :email
              AND Password__c = :password
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            res.success = false;
            res.message = 'Invalid email or password.';
            return res;
        }

        Id contactId = matches[0].Id;

        // 2) Projects for this contact
        List<Project__c> projects = [
            SELECT Id,
                   Name,
                   Status__c,
                   Start_Date__c,
                   Estimated_End_Date__c,
                   Estimated_Project_Duration__c,
                   Project_Completion_Status__c      // NEW
            FROM Project__c
            WHERE Client__c = :contactId
            ORDER BY CreatedDate DESC
        ];

        if (projects.isEmpty()) {
            res.success = true;
            res.message = 'No projects found for this contact.';
            return res;
        }

        // 3) Vendor Assignments
        Set<Id> projectIds = new Set<Id>();
        for (Project__c p : projects) {
            projectIds.add(p.Id);
        }

        List<Vendor_Assignment__c> vaRecords = [
            SELECT Id,
                   Name,
                   Project__c,
                   Vendor__r.Name,
                   Vendor_Category__c,
                   Status__c,
                   Vendor_Work_Start_Date__c,
                   Vendor_Work_End_Date__c,
                   Number_of_Days__c,
                   Vendor_Amount__c,
                   Completion__c                      // NEW
            FROM Vendor_Assignment__c
            WHERE Project__c IN :projectIds
        ];

        Map<Id, List<VendorAssignmentDTO>> projToVADtos =
            new Map<Id, List<VendorAssignmentDTO>>();
        Map<Id, VendorAssignmentDTO> vaIdToDto =
            new Map<Id, VendorAssignmentDTO>();
        Set<Id> vaIds = new Set<Id>();

        for (Vendor_Assignment__c va : vaRecords) {
            vaIds.add(va.Id);

            VendorAssignmentDTO dto = new VendorAssignmentDTO();
            dto.id             = va.Id;
            dto.name           = va.Name;
            dto.vendorName     = (va.Vendor__r != null) ? va.Vendor__r.Name : null;
            dto.category       = va.Vendor_Category__c;
            dto.status         = va.Status__c;
            dto.workStartDate  = va.Vendor_Work_Start_Date__c;
            dto.workEndDate    = va.Vendor_Work_End_Date__c;
            dto.workDuration   = (va.Number_of_Days__c == null)
                                 ? null
                                 : Integer.valueOf(va.Number_of_Days__c);
            dto.amount         = va.Vendor_Amount__c;
            dto.completionPercent = va.Completion__c;   // NEW
            dto.tasks          = new List<TaskDTO>();

            vaIdToDto.put(va.Id, dto);

            List<VendorAssignmentDTO> bucket = projToVADtos.get(va.Project__c);
            if (bucket == null) {
                bucket = new List<VendorAssignmentDTO>();
                projToVADtos.put(va.Project__c, bucket);
            }
            bucket.add(dto);
        }

        // 4) Tasks (kept for table only – not for % calc)
        if (!vaIds.isEmpty()) {
            for (Task t : [
                SELECT Id,
                       Subject,
                       Status,
                       Start_Date__c,
                       ActivityDate,
                       Assigned_Percentage__c,
                       Final_Task_Completed_Date__c,
                       Number_of_Days__c,
                       WhatId
                FROM Task
                WHERE WhatId IN :vaIds
                ORDER BY ActivityDate
            ]) {
                VendorAssignmentDTO vaDto = vaIdToDto.get(t.WhatId);
                if (vaDto == null) continue;

                TaskDTO td = new TaskDTO();
                td.id                 = t.Id;
                td.subject            = t.Subject;
                td.status             = t.Status;
                td.startDate          = t.Start_Date__c;
                td.dueDate            = t.ActivityDate;
                td.assignedPercent    = t.Assigned_Percentage__c;
                td.finalCompletedDate = t.Final_Task_Completed_Date__c;
                td.numberOfDays       = (t.Number_of_Days__c == null)
                                        ? null
                                        : Integer.valueOf(t.Number_of_Days__c);

                vaDto.tasks.add(td);
            }
        }

        // 5) Build Project DTOs
        for (Project__c p : projects) {
            ProjectDTO pd = new ProjectDTO();
            pd.id                = p.Id;
            pd.name              = p.Name;
            pd.status            = p.Status__c;
            pd.startDate         = p.Start_Date__c;
            pd.endDate           = p.Estimated_End_Date__c;
            pd.estimatedDuration = p.Estimated_Project_Duration__c;
            pd.completionPercent = p.Project_Completion_Status__c;   // NEW
            pd.vendorAssignments =
                projToVADtos.containsKey(p.Id)
                ? projToVADtos.get(p.Id)
                : new List<VendorAssignmentDTO>();

            res.projects.add(pd);
        }

        res.success = true;
        res.message = 'Success';
        return res;
    }
}
