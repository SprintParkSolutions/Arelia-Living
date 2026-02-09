@RestResource(urlMapping='/supervisor/leadfiles/*')
global with sharing class SupervisorLeadFilesController {

    global class FileDTO {
        public String documentId;
        public String title;
        public String fileType;
        public Long fileSize;
        public String downloadUrl;
    }

    @HttpGet
    global static void getFiles() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String leadId = req.requestURI.substringAfterLast('/');
        List<FileDTO> out = new List<FileDTO>();

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.ContentSize
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :leadId
            ORDER BY ContentDocument.CreatedDate DESC
        ]) {
            FileDTO f = new FileDTO();
            f.documentId = cdl.ContentDocumentId;
            f.title = cdl.ContentDocument.Title;
            f.fileType = cdl.ContentDocument.FileType;
            f.fileSize = cdl.ContentDocument.ContentSize;

            // ✅ Works in new API versions
            f.downloadUrl =
                baseUrl +
                '/sfc/servlet.shepherd/document/download/' +
                cdl.ContentDocumentId;

            out.add(f);
        }

        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}