public without sharing class OpportunityQuotePDFController {

    /* ===============================
       PROPERTIES USED BY VF
    =============================== */
    public Opportunity Opp { get; private set; }
    public List<Project_Specification__c> specItems { get; private set; }
    public Decimal grandTotal { get; private set; }
    public Datetime generatedOn { get; private set; } 

    /* ===============================
       VF CONTROLLER (PDF RENDER)
    =============================== */
    public OpportunityQuotePDFController() {

        generatedOn = Datetime.now();
        specItems = new List<Project_Specification__c>();
        grandTotal = 0;

        Id oppId = ApexPages.currentPage().getParameters().get('id');
        if (oppId == null) return;

        // 🔹 Load Opportunity
        Opp = [
            SELECT Id, Name, Lead_Name__c, Email__c, Lead_Phone__c,
                   Type_of_Project__c,
                   Supervisor_User__c
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        // 🔹 Load ONLY active cart items
        specItems = [
            SELECT Quantity__c, Unit_Price__c, Total_Amount__c,
                   Quality__c, Vendor_Category__c,
                   Interior_Product__r.Name,
                   Interior_Product__r.Product_Category__c,
                   Interior_Product__r.Room_Type__c
            FROM Project_Specification__c
            WHERE Opportunity__c = :oppId
            AND Is_Active_Cart_Item__c = TRUE
            ORDER BY CreatedDate ASC
        ];

        // 🔹 Calculate grand total
        for (Project_Specification__c s : specItems) {
            if (s.Total_Amount__c != null) {
                grandTotal += s.Total_Amount__c;
            }
        }
    }


    /* ===============================
       CART OPERATIONS
    =============================== */

    /* 👉 Load active items into LWC cart */
    @AuraEnabled(cacheable=true)
    public static List<Project_Specification__c> getSavedCart(Id opportunityId) {
        return [
            SELECT Id, Name, Interior_Product__c,
       Quantity__c, Unit_Price__c, Total_Amount__c,
       Quality__c, Vendor_Category__c, Is_Active_Cart_Item__c,
       Room_Type__c, Product_Category__c
FROM Project_Specification__c
WHERE Opportunity__c = :opportunityId
AND Is_Active_Cart_Item__c = TRUE
ORDER BY LastModifiedDate DESC
        ];
    }


    /* ❗ Save cart:
       - mark previous items inactive
       - insert new items as active
    */
    @AuraEnabled
    public static void saveCart(Id opportunityId, List<Project_Specification__c> cartItems) {

        if (opportunityId == null || cartItems == null || cartItems.isEmpty()) {
            throw new AuraHandledException('Nothing to save');
        }

        // 1️⃣ Mark previous cart items inactive
        List<Project_Specification__c> oldItems = [
            SELECT Id 
            FROM Project_Specification__c
            WHERE Opportunity__c = :opportunityId
            AND Is_Active_Cart_Item__c = TRUE
        ];

        for(Project_Specification__c item : oldItems){
            item.Is_Active_Cart_Item__c = FALSE;
        }
        if(!oldItems.isEmpty()) update oldItems;


        // 2️⃣ Fetch required product fields (❗ FIXED HERE)
        Set<Id> productIds = new Set<Id>();
        for (Project_Specification__c ci : cartItems) {
            if (ci.Interior_Product__c != null) {
                productIds.add(ci.Interior_Product__c);
            }
        }

        Map<Id, Interior_Product__c> productMap = new Map<Id, Interior_Product__c>(
            [SELECT Id, Room_Type__c, Product_Category__c 
             FROM Interior_Product__c 
             WHERE Id IN :productIds]
        );

        // 3️⃣ Insert new items as ACTIVE
        for (Project_Specification__c ci : cartItems) {
            ci.Opportunity__c = opportunityId;
            ci.Is_Active_Cart_Item__c = TRUE;

            Interior_Product__c prod = productMap.get(ci.Interior_Product__c);
            if (prod != null) {
                ci.Room_Type__c = prod.Room_Type__c;
                ci.Product_Category__c = prod.Product_Category__c;
                ci.Vendor_Category__c = prod.Product_Category__c; // Optional
            }
        }

        insert cartItems;
    }


    /* 🗑 Remove one item (deactivate only) */
    @AuraEnabled
    public static void deactivateCartItem(Id specItemId) {
        if (specItemId == null) return;

        Project_Specification__c item = [
            SELECT Id, Is_Active_Cart_Item__c
            FROM Project_Specification__c
            WHERE Id = :specItemId
            LIMIT 1
        ];
        item.Is_Active_Cart_Item__c = FALSE;
        update item;
    }


    /* ===============================
       GENERATE QUOTE + PDF
    =============================== */
    @AuraEnabled
    public static String generateQuoteAndSave(Id opportunityId) {

        if (opportunityId == null)
            throw new AuraHandledException('Opportunity Id missing');

        List<Project_Specification__c> cartItems = [
            SELECT Interior_Product__c, Quantity__c, Unit_Price__c,
                   Quality__c, Vendor_Category__c
            FROM Project_Specification__c
            WHERE Opportunity__c = :opportunityId
            AND Is_Active_Cart_Item__c = TRUE
        ];

        if (cartItems.isEmpty())
            throw new AuraHandledException('Cart is empty. Save items first.');

        Quotation__c qt = new Quotation__c(
            Opportunity__c = opportunityId,
            Name = 'Quotation - ' + Datetime.now().format('yyyyMMdd_HHmmss'),
            Manager_Approval__c = false
        );
        insert qt;

        PageReference pageRef = Page.Opportunity_Quote_PDF;
        pageRef.getParameters().put('id', opportunityId);

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('TEST PDF')
            : pageRef.getContentAsPDF();

        Attachment att = new Attachment(
            ParentId    = qt.Id,
            Name        = 'Quotation.pdf',
            Body        = pdfBlob,
            ContentType = 'application/pdf'
        );
        insert att;

        System.enqueueJob(new PdfGeneratorAsync(opportunityId, att.Id));

        return 'SUCCESS';
    }


    /* ===============================
       ORG-WIDE EMAIL
    =============================== */
    public static Id getOWD() {
        List<OrgWideEmailAddress> ow = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true
            LIMIT 1
        ];
        return ow.isEmpty() ? null : ow[0].Id;
    }
}