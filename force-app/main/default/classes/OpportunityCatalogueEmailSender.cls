public with sharing class OpportunityCatalogueEmailSender {

    public static void sendCatalogueEmail(List<Id> oppIds) {

        List<Opportunity> oppList = [
            SELECT Id, Lead_Name__c, Email__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];

        EmailTemplate tpl = [
            SELECT Id, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName = 'Opportunity_Catalogue_Link'
            LIMIT 1
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : oppList) { 

            
            String inventoryCatalogueLink = Label.Arelia_Site_Label+ Label.Inventory_Catalogue_Site_Base + '?id=' + opp.Id;

           String html = tpl.HtmlValue
                 .replace('{{{CustomerName}}}', opp.Lead_Name__c)
               
                   .replace('{{{catalogueLink}}}', inventoryCatalogueLink);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ opp.Email__c });
            msg.setSubject(tpl.Subject);
            msg.setHtmlBody(html);
            msg.setWhatId(opp.Id);
            msg.setSaveAsActivity(true);
            msg.setOrgWideEmailAddressId(getOWD());
            emails.add(msg);
        }

        Messaging.sendEmail(emails);
    }

    private static Id getOWD() {
        List<OrgWideEmailAddress> listOWEA = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true LIMIT 1
        ];
        return !listOWEA.isEmpty() ? listOWEA[0].Id : null;
    }
}