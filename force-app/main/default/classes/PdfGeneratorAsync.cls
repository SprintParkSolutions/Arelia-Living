public class PdfGeneratorAsync {
    @future(callout=true)
    public static void generatePdf(Id opportunityId) {

        PageReference pageRef = Page.Opportunity_Quote_PDF;
        pageRef.getParameters().put('opportunityId', opportunityId);

        Blob pdfBlob = pageRef.getContentAsPDF();

        Attachment att = new Attachment(
            Name = 'Quotation_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.pdf',
            ParentId = opportunityId,
            Body = pdfBlob,
            ContentType = 'application/pdf'
        );
        insert att;
    }
}