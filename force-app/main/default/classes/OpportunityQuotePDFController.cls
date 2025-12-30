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

        // VF is called with ?id=<OpportunityId>
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

        // 🔹 Load CURRENT cart items only
        specItems = [
            SELECT Quantity__c,
                   Unit_Price__c,
                   Total_Amount__c,
                   Quality__c,
                   Vendor_Category__c,
                   Interior_Product__r.Name,
                   Interior_Product__r.Product_Category__c,
                   Interior_Product__r.Room_Type__c
            FROM Project_Specification__c
            WHERE Opportunity__c = :oppId
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
       SAVE CART + CREATE QUOTE
    =============================== */
    /* -------------------- SAVE CART ITEMS -------------------- */
    @AuraEnabled(cacheable=true)
public static List<Project_Specification__c> getSavedCart(Id opportunityId) {
    if (opportunityId == null) return new List<Project_Specification__c>();

    return [
        SELECT Id, Name, Opportunity__c, Interior_Product__c,
               Quantity__c, Unit_Price__c, Total_Amount__c,
               Quality__c, Vendor_Category__c
        FROM Project_Specification__c
        WHERE Opportunity__c = :opportunityId
        ORDER BY CreatedDate ASC
    ];
}
    @AuraEnabled
public static void saveCart(Id opportunityId, List<Project_Specification__c> cartItems) {

    if (opportunityId == null || cartItems == null || cartItems.isEmpty()) {
        throw new AuraHandledException('Nothing to save');
    }

    // --------------------------------------
    // 1️⃣ Delete old cart items for this opp
    // --------------------------------------
    /*delete [
        SELECT Id 
        FROM Project_Specification__c
        WHERE Opportunity__c = :opportunityId
    ];*/

    // --------------------------------------
    // 2️⃣ Collect product IDs from cart items
    // --------------------------------------
    Set<Id> productIds = new Set<Id>();
    for (Project_Specification__c ci : cartItems) {
        if (ci.Interior_Product__c != null) {
            productIds.add(ci.Interior_Product__c);
        }
    }

    // --------------------------------------
    // 3️⃣ Query correct product object
    //     (Vendor category stored here)
    // --------------------------------------
    Map<Id, Interior_Product__c> productMap =
        new Map<Id, Interior_Product__c>(
            [SELECT Id, Product_Category__c
             FROM Interior_Product__c
             WHERE Id IN :productIds]
        );

    // --------------------------------------
    // 4️⃣ Assign Opportunity and Vendor Category
    //     before inserting cart items
    // --------------------------------------
    for (Project_Specification__c ci : cartItems) {
        ci.Opportunity__c = opportunityId;

        Interior_Product__c prod = productMap.get(ci.Interior_Product__c);
        if (prod != null && prod.Product_Category__c != null) {
            ci.Vendor_Category__c = prod.Product_Category__c;
        }
    }

    // --------------------------------------
    // 5️⃣ Insert fresh cart items
    // --------------------------------------
    insert cartItems;
}

    /* -------------------- GENERATE QUOTE & PDF -------------------- */
    @AuraEnabled
    public static String generateQuoteAndSave(Id opportunityId) {

        if (opportunityId == null)
            throw new AuraHandledException('Opportunity Id missing');

        // 1️⃣ Load saved cart
        List<Project_Specification__c> cartItems = [
            SELECT Interior_Product__c, Quantity__c, Unit_Price__c, Quality__c,Vendor_Category__c
            FROM Project_Specification__c
            WHERE Opportunity__c = :opportunityId
        ];

        if (cartItems.isEmpty())
            throw new AuraHandledException('Cart is empty. Save items first.');

        // 2️⃣ Create quotation
        Quotation__c qt = new Quotation__c(
            Opportunity__c = opportunityId,
            Name = 'Quotation - ' + Datetime.now().format('yyyyMMdd_HHmmss'),
            Manager_Approval__c = false
        );
        insert qt;

        // 3️⃣ Generate PDF
        PageReference pageRef = Page.Opportunity_Quote_PDF;
        pageRef.getParameters().put('id', opportunityId);

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('TEST PDF')
            : pageRef.getContentAsPDF();

        // 4️⃣ Attach PDF
        Attachment att = new Attachment(
            ParentId    = qt.Id,
            Name        = 'Quotation.pdf',
            Body        = pdfBlob,
            ContentType = 'application/pdf'
        );
        insert att;

        // 5️⃣ Send email async
        System.enqueueJob(new PdfGeneratorAsync(opportunityId, att.Id));

        return 'SUCCESS';
    }


    /* ===============================
       ORG WIDE EMAIL
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