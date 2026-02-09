@RestResource(urlMapping='/supervisor/lead/upload/*')
global with sharing class SupervisorLeadUploadController {

    global class FilePayload {
        public String fileName;
        public String base64Data;
    }

    global class UploadResponse {
        public Boolean success;
        public Integer uploaded;
        public String message;
    }

    @HttpPost
    global static void upload() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        String leadId = req.requestURI.substringAfterLast('/');

        UploadResponse out = new UploadResponse();
        out.uploaded = 0;

        try {
            List<FilePayload> files = (List<FilePayload>)JSON.deserialize(
                req.requestBody.toString(),
                List<FilePayload>.class
            );

            List<ContentVersion> cvs = new List<ContentVersion>();

            for (FilePayload f : files) {
                if (f == null || String.isBlank(f.fileName) || String.isBlank(f.base64Data)) continue;

                ContentVersion cv = new ContentVersion();
                cv.Title = f.fileName;
                cv.PathOnClient = '/' + f.fileName;
                cv.VersionData = EncodingUtil.base64Decode(f.base64Data);
                cvs.add(cv);
            }

            if (!cvs.isEmpty()) {
                insert cvs;

                // Link docs to Lead
                List<ContentDocumentLink> links = new List<ContentDocumentLink>();

                for (ContentVersion cvInserted : [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE Id IN :cvs
                ]) {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.LinkedEntityId = leadId;
                    cdl.ContentDocumentId = cvInserted.ContentDocumentId;
                    cdl.ShareType = 'V';
                    cdl.Visibility = 'AllUsers';
                    links.add(cdl);
                }

                insert links;
                out.uploaded = cvs.size();
            }

            out.success = true;

        } catch (Exception e) {
            out.success = false;
            out.message = e.getMessage();
            res.statusCode = 500;
        }

        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}