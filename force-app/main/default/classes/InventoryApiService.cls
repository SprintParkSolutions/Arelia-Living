public without sharing class InventoryApiService {

    /* ===============================
       STEP 1 + STEP 2
       Fetch Room Types & Categories
       based on Opportunity context
    =============================== */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCatalogConfig(Id opportunityId) {

        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required');
        }

        // 1️⃣ Get Opportunity context
        Opportunity opp = [
            SELECT Type_of_Project__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (String.isBlank(opp.Type_of_Project__c)) {
            throw new AuraHandledException('Type of Project is not set on Opportunity');
        }

        // 2️⃣ Get product-based configuration
        List<Interior_Product__c> products = [
            SELECT Room_Type__c, Product_Category__c
            FROM Interior_Product__c
            WHERE Type_of_Project__c = :opp.Type_of_Project__c
        ];

        // 3️⃣ Build dynamic dependency structure
        Set<String> roomSet = new Set<String>();
        Map<String, Set<String>> categoryMap = new Map<String, Set<String>>();

        for (Interior_Product__c p : products) {
            if (String.isBlank(p.Room_Type__c) || String.isBlank(p.Product_Category__c)) {
                continue;
            }

            roomSet.add(p.Room_Type__c);

            if (!categoryMap.containsKey(p.Room_Type__c)) {
                categoryMap.put(p.Room_Type__c, new Set<String>());
            }
            categoryMap.get(p.Room_Type__c).add(p.Product_Category__c);
        }

        // 4️⃣ Convert Sets → Lists (LWC-friendly)
        Map<String, Object> result = new Map<String, Object>();
        result.put('rooms', new List<String>(roomSet));

        Map<String, List<String>> finalCategoryMap = new Map<String, List<String>>();
        for (String room : categoryMap.keySet()) {
            finalCategoryMap.put(room, new List<String>(categoryMap.get(room)));
        }

        result.put('categoriesByRoom', finalCategoryMap);
        return result;
    }


    /* ===============================
       STEP 3
       Load Products (UNCHANGED)
    =============================== */
    @AuraEnabled(cacheable=true)
    public static List<Interior_Product__c> getProducts(String roomType, String category) {

        if (String.isBlank(roomType) || String.isBlank(category)) {
            return new List<Interior_Product__c>();
        }

        return [
            SELECT Id, Name, Product_Category__c, Room_Type__c,
                   Unit_Price__c, Image_File_Name__c
            FROM Interior_Product__c
            WHERE Room_Type__c = :roomType
            AND Product_Category__c = :category
            ORDER BY Name
        ];
    }
}