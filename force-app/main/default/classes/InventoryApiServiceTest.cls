@IsTest
@SuppressWarnings('PMD.ApexAssertionsShouldIncludeMessage')
private class InventoryApiServiceTest {

    @TestSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('invUser');

        // 2. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Inventory Opp', u.Id);
        // CRITICAL: Updated to 'Home' per your requirement
        opp.Type_of_Project__c = 'Home'; 
        opp.Email__c = 'testclient@example.com'; 
        update opp;

        // 3. Create Products using Utility
        
        // Item 1: Matching Room/Category AND Project Type ('Home')
        Interior_Product__c p1 = TestDataUtility.createInteriorProduct('Accent Wall', 'Dining Hall', 'Painting & Wall Finishing', 1500);
        p1.Type_of_Project__c = 'Home';
        update p1;

        // Item 2: Matching Room/Category AND Project Type ('Home')
        Interior_Product__c p2 = TestDataUtility.createInteriorProduct('Textured Paint', 'Dining Hall', 'Painting & Wall Finishing', 300);
        p2.Type_of_Project__c = 'Home';
        update p2;

        // Item 3: Different Room, different Project Type ('Office')
        Interior_Product__c p3 = TestDataUtility.createInteriorProduct('Electrical board set', 'Living Room', 'Electrical & Networking', 2000);
        p3.Type_of_Project__c = 'Office'; // Should be excluded by getCatalogConfig for 'Home' opps
        update p3;

        // Item 4: Different Category, Matching Type ('Home')
        Interior_Product__c p4 = TestDataUtility.createInteriorProduct('Wooden chairs reception', 'Reception', 'Carpentry & Woodwork', 50);
        p4.Type_of_Project__c = 'Home';
        update p4;
    }

    // ==========================================
    // 1. Tests for getCatalogConfig
    // ==========================================

    @IsTest
    static void testGetCatalogConfigSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Map<String, Object> result = InventoryApiService.getCatalogConfig(opp.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Result map should not be null');

        // 1. Validate Rooms List
        // Should find 'Dining Hall' (from p1, p2) and 'Reception' (from p4) which are 'Home'
        List<String> rooms = (List<String>) result.get('rooms'); 
        Assert.isNotNull(rooms, 'Rooms list should not be null');
        Assert.isTrue(rooms.contains('Dining Hall'), 'Should contain Home room: Dining Hall');
        Assert.isTrue(rooms.contains('Reception'), 'Should contain Home room: Reception');
        Assert.isFalse(rooms.contains('Living Room'), 'Should NOT contain Office room: Living Room');

        // 2. Validate Categories Map
        Map<String, List<String>> catMap = (Map<String, List<String>>) result.get('categoriesByRoom');
        Assert.isNotNull(catMap, 'Category map should not be null');
        
        // Check Dining Hall categories
        Assert.isTrue(catMap.containsKey('Dining Hall'));
        List<String> diningCats = catMap.get('Dining Hall');
        Assert.isTrue(diningCats.contains('Painting & Wall Finishing'), 'Should contain Painting category');
    }

    @IsTest
    static void testGetCatalogConfigNullId() {
        Test.startTest();
        try {
            InventoryApiService.getCatalogConfig(null);
            Assert.fail('Should throw exception for null Id');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should be AuraHandledException');
        }
        Test.stopTest();
    }

    // ==========================================
    // 2. Tests for getOpportunitySummary
    // ==========================================

    @IsTest
    static void testGetOpportunitySummary() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Opportunity result = InventoryApiService.getOpportunitySummary(opp.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Should return Opportunity record');
        Assert.areEqual('Home', result.Type_of_Project__c, 'Project Type should match Home');
        Assert.areEqual('testclient@example.com', result.Email__c, 'Email should match');
    }

    // ==========================================
    // 3. Existing Tests for getProducts (Maintained)
    // ==========================================

    @IsTest
    static void testGetProductsSuccess() {
        Test.startTest();
        // Query matches Setup Data (Dining Hall / Painting)
        List<Interior_Product__c> results = InventoryApiService.getProducts('Dining Hall', 'Painting & Wall Finishing');
        Test.stopTest();

        Assert.isNotNull(results, 'Should return a list');
        Assert.areEqual(2, results.size(), 'Should return exactly 2 matching records');
        
        // Verify sorting (ORDER BY Name ASC)
        Assert.areEqual('Accent Wall', results[0].Name, 'Should be sorted by Name ASC');
        Assert.areEqual('Textured Paint', results[1].Name);
    }

    @IsTest
    static void testGetProductsNoMatch() {
        Test.startTest();
        List<Interior_Product__c> results = InventoryApiService.getProducts('Kitchen', 'Appliances');
        Test.stopTest();

        Assert.isNotNull(results, 'Should return empty list, not null');
        Assert.areEqual(0, results.size(), 'Should find 0 records');
    }

    @IsTest
    static void testGetProductsPartialMatch() {
        Test.startTest();
        List<Interior_Product__c> results = InventoryApiService.getProducts('Dining Hall', 'Flooring & Tiling');
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Should strictly match both fields');
    }

    @IsTest
    static void testGetProductsNullParams() {
        Test.startTest();
        List<Interior_Product__c> results = InventoryApiService.getProducts(null, null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Should return empty list for null parameters');
    }
}