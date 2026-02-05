public with sharing class FieldLabelUtil {

    private static Map<String, String> leadLabelMap;

    public static String getLeadLabel(String apiName) {
        if (leadLabelMap == null) {
            leadLabelMap = new Map<String, String>();
            Map<String, Schema.SObjectField> fields =
                Schema.SObjectType.Lead.fields.getMap();

            for (String key : fields.keySet()) {
                leadLabelMap.put(
                    key,
                    fields.get(key).getDescribe().getLabel()
                );
            }
        }
        return leadLabelMap.get(apiName);
    }
}