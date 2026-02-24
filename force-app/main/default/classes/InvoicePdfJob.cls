public with sharing class InvoicePdfJob implements Queueable, Database.AllowsCallouts {
    private final Id invoiceId;

    public InvoicePdfJob(Id invoiceId) {
        this.invoiceId = invoiceId;
    }

    public void execute(QueueableContext qc) {
        if (invoiceId == null) return;

        // ✅ Query invoice + opportunity name for file title
        // CHANGE FIELD NAME HERE if your lookup is not Opportunity__c
        List<Invoice__c> invList = [
            SELECT Id, Name, Invoice_No__c, Opportunity__c, Opportunity__r.Name
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
        if (invList.isEmpty()) return;

        Invoice__c inv = invList[0];

        String oppName = (inv.Opportunity__c != null && inv.Opportunity__r != null)
            ? inv.Opportunity__r.Name
            : inv.Name;

        String safeBase = sanitizeFileName('Invoice_' + oppName);
        String fileTitle = safeBase;
        String fileName  = safeBase + '.pdf';

        PageReference pr = Page.InvoicePdf;
        pr.getParameters().put('id', String.valueOf(invoiceId));

        Blob pdfBlob;
        try {
            if (Test.isRunningTest()) {
                pdfBlob = Blob.valueOf('DUMMY_PDF');
            } else {
                pdfBlob = pr.getContentAsPDF();
            }
        } catch (Exception e) {
            try {
                update new Invoice__c(Id = invoiceId, PDF_Error__c = e.getMessage());
            } catch (Exception ignore) {}
            return;
        }

        ContentVersion cv = new ContentVersion();
        cv.Title = fileTitle;          // ✅ Title shows Invoice_<Opportunity Name>
        cv.PathOnClient = fileName;    // ✅ Invoice_<Opportunity Name>.pdf
        cv.VersionData = pdfBlob;
        insert cv;

        List<ContentVersion> cv2 = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        if (cv2.isEmpty() || cv2[0].ContentDocumentId == null) return;

        Id docId = cv2[0].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = invoiceId;
        cdl.ContentDocumentId = docId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;

        try {
            update new Invoice__c(Id = invoiceId, PDF_ContentDocumentId__c = docId);
        } catch (Exception ignore2) {}
    }

    // ✅ Remove characters not allowed in file names
    private static String sanitizeFileName(String inputName) {
        String v = String.isBlank(inputName) ? 'Invoice' : inputName.trim();
        v = v.replaceAll('[\\\\/:*?"<>|]', ' '); // illegal filename chars
        v = v.replaceAll('\\s+', ' ').trim();    // collapse spaces
        if (v.length() > 80) v = v.substring(0, 80);
        return v;
    }
}
