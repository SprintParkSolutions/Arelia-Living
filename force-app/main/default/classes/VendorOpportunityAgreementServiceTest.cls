@isTest
public class VendorOpportunityAgreementServiceTest {

    @testSetup
    static void setupData() {
        // 1. Create Supervisor using Utility
        User supervisor = TestDataUtility.createSupervisorUser('SupAgree');

        // 2. Create Opportunity using Utility
        Opportunity opp = TestDataUtility.createOpportunity('Agreement Opp', supervisor.Id);
        // Ensure flag starts as false
        opp.All_Vendors_Agreement_Completed__c = false;
        update opp;

        // 3. Create Vendors using Utility
        Vendor__c v1 = TestDataUtility.createVendor('Vendor One', 'Carpentry & Woodwork', 'v1@test.com');
        Vendor__c v2 = TestDataUtility.createVendor('Vendor Two', 'Electrical & Networking', 'v2@test.com');

        // 4. Create Vendor Opportunities (Not Signed initially) using Utility
        Vendor_Opportunity__c vo1 = TestDataUtility.createVendorOpportunity(opp.Id, v1.Id, 'Active');
        // Utility sets status but boolean flag might need manual update if not defaulted
        vo1.Vendor_Agreement_Signed__c = false;
        update vo1;

        Vendor_Opportunity__c vo2 = TestDataUtility.createVendorOpportunity(opp.Id, v2.Id, 'Active');
        vo2.Vendor_Agreement_Signed__c = false;
        update vo2;

        // 5. Create a File for one Vendor Opportunity to test Copy Logic using Utility
        ContentVersion cv = TestDataUtility.createContentVersion('Vendor Agreement Doc', 'Signed Contract');
        TestDataUtility.linkFileToRecord(cv.Id, vo1.Id);
    }

    @isTest
    static void testPartialCompletion() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Vendor_Opportunity__c vo1 = [SELECT Id FROM Vendor_Opportunity__c WHERE Vendor__r.Name = 'Vendor One' LIMIT 1];

        // Action: Sign only ONE vendor
        vo1.Vendor_Agreement_Signed__c = true;
        update vo1;

        Test.startTest();
        // Manually invoke service (simulating Trigger)
        VendorOpportunityAgreementService.recalculateAndCopyFiles(new Set<Id>{opp.Id});
        Test.stopTest();

        // Verify: Opportunity flag should still be FALSE (waiting for Vendor Two)
        Opportunity result = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, result.All_Vendors_Agreement_Completed__c, 'Opp should not be complete if one vendor is pending');
    }

    @isTest
    static void testFullCompletionAndFileCopy() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Vendor_Opportunity__c> vos = [SELECT Id FROM Vendor_Opportunity__c];

        // Action: Sign ALL vendors
        for (Vendor_Opportunity__c vo : vos) {
            vo.Vendor_Agreement_Signed__c = true;
        }
        update vos;

        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(new Set<Id>{opp.Id});
        Test.stopTest();

        // Verify 1: Flag is TRUE
        Opportunity result = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, result.All_Vendors_Agreement_Completed__c, 'Opp should be complete when all vendors sign');

        // Verify 2: File was copied to Opportunity
        List<ContentDocumentLink> oppLinks = [
            SELECT ContentDocument.Title 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :opp.Id 
        ];
        
        System.assertEquals(1, oppLinks.size(), 'File from Vendor Opp should be copied to Parent Opp');
        System.assertEquals('Vendor Agreement Doc', oppLinks[0].ContentDocument.Title, 'File title should match the original');
    }

    @isTest
    static void testReversionToFalse() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Vendor_Opportunity__c> vos = [SELECT Id FROM Vendor_Opportunity__c];

        // 1. Set all to Signed first
        for (Vendor_Opportunity__c vo : vos) {
            vo.Vendor_Agreement_Signed__c = true;
        }
        update vos;
        VendorOpportunityAgreementService.recalculateAndCopyFiles(new Set<Id>{opp.Id});

        // Verify initial state is TRUE
        Opportunity midResult = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(true, midResult.All_Vendors_Agreement_Completed__c, 'Initial state should be true before unsigning');

        Test.startTest();
        // 2. Unsign one vendor
        vos[0].Vendor_Agreement_Signed__c = false;
        update vos[0];
        
        VendorOpportunityAgreementService.recalculateAndCopyFiles(new Set<Id>{opp.Id});
        Test.stopTest();

        // Verify: Flag flips back to FALSE
        Opportunity endResult = [SELECT All_Vendors_Agreement_Completed__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(false, endResult.All_Vendors_Agreement_Completed__c, 'Opp should revert to false if a vendor is unsigned');
    }

    @isTest
    static void testEmptyInput() {
        Test.startTest();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(new Set<Id>());
        VendorOpportunityAgreementService.recalculateAndCopyFiles(null);
        Test.stopTest();
        
        System.assert(true, 'Should handle empty/null input gracefully');
    }
    
    @isTest
    static void testBulkOperations() {
        User sup = [SELECT Id FROM User WHERE Alias = 'SupAgree' LIMIT 1];
        Vendor__c v = [SELECT Id FROM Vendor__c LIMIT 1];
        
        // Create 5 Opps, each with 1 signed vendor
        // Using standard list instantiation for bulk creation efficiency in test
        List<Opportunity> newOpps = new List<Opportunity>();
        for(Integer i=0; i<5; i++) {
            newOpps.add(new Opportunity(
                Name='Bulk Opp '+i, 
                StageName='Prospecting', 
                CloseDate=Date.today(), 
                Supervisor_User__c=sup.Id
            ));
        }
        insert newOpps;
        
        List<Vendor_Opportunity__c> newVos = new List<Vendor_Opportunity__c>();
        for(Opportunity o : newOpps) {
            newVos.add(new Vendor_Opportunity__c(
                Opportunity__c = o.Id, 
                Vendor__c = v.Id, 
                Vendor_Agreement_Signed__c = true // Already signed
            ));
        }
        insert newVos;
        
        Test.startTest();
        // Pass all IDs at once
        Set<Id> oppIds = new Map<Id, Opportunity>(newOpps).keySet();
        VendorOpportunityAgreementService.recalculateAndCopyFiles(oppIds);
        Test.stopTest();
        
        // Verify all 5 flipped to True
        List<Opportunity> results = [SELECT Id FROM Opportunity WHERE Id IN :oppIds AND All_Vendors_Agreement_Completed__c = true];
        System.assertEquals(5, results.size(), 'All bulk opportunities should be updated');
    }
}