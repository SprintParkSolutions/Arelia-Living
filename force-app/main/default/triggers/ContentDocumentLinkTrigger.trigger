trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {// NOPMD
    List<ContentDocumentLink> toUpdate = new List<ContentDocumentLink>();

    for (ContentDocumentLink cdl : Trigger.new) {
        // only for files linked to Interior_Design__c
        if (cdl.LinkedEntityId != null && cdl.LinkedEntityId.getSObjectType() == Interior_Design__c.SObjectType) {
            ContentDocumentLink cloneCdl = cdl.clone(false, false, false, false);
            cloneCdl.Id       = cdl.Id;
            cloneCdl.ShareType = 'V';
            cloneCdl.Visibility = 'AllUsers';
            toUpdate.add(cloneCdl);
        }
    }

    if (!toUpdate.isEmpty()) {// NOPMD
        update toUpdate;
    }
}