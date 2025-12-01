/**
 * @File Name      : RegistrationFormController.cls
 * @description    : Handles registration form operations - email verification and lead creation.
 * @author         : Arelia Living
 */
public without sharing class RegistrationFormController {

    private static Id cachedWelcomeTemplateId;
    private static EmailTemplate cachedVerificationTemplate;

    // ----------------------------------------------------------------------
    // Public API – Send OTP verification email (template only)
    // ----------------------------------------------------------------------

    /**
     * @description Sends an OTP verification email using the verification email template.
     * The email content is taken entirely from the template and token {{{VerificationCode}}}
     * is replaced with the runtime verificationCode.
     * @param email            Email address to which OTP should be sent.
     * @param verificationCode Generated OTP to include in the email.
     */
    @AuraEnabled
    public static void sendVerificationEmail(String email, String verificationCode) {
        validateEmail(email);
        ensureVerificationCodeProvided(verificationCode);

        EmailTemplate template = requireVerificationTemplate();
        Messaging.SingleEmailMessage msg =
            buildVerificationEmailMessage(email, verificationCode, template);

        setOrgWideAddressForGuest(msg);
        msg.setSaveAsActivity(true);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    /**
     * @description Ensures verification code is not blank.
     * @param verificationCode Generated OTP.
     */
    private static void ensureVerificationCodeProvided(String verificationCode) {
        if (String.isBlank(verificationCode)) {
            throw new AuraHandledException('Verification code is required.');
        }
    }

    /**
     * @description Returns a verification email template and validates that it is usable.
     * @return EmailTemplate configured via custom label.
     */
    private static EmailTemplate requireVerificationTemplate() {
        EmailTemplate tpl = getVerificationTemplate();
        if (tpl == null) {
            // Config issue only; no fallback body
            throw new AuraHandledException(
                'Verification email template is not configured. Please contact support.'
            );
        }

        // Template MUST have some body
        if (String.isBlank(tpl.Body) && String.isBlank(tpl.HtmlValue)) {
            throw new AuraHandledException(
                'Verification email template has no body. Please contact support.'
            );
        }
        return tpl;
    }

    /**
     * @description Builds the SingleEmailMessage for verification email using template
     * subject/body and replacing the {{{VerificationCode}}} token.
     * @param email            Recipient email address.
     * @param verificationCode OTP code to inject.
     * @param template         Email template used for subject and body.
     * @return SingleEmailMessage ready to be sent.
     */
    private static Messaging.SingleEmailMessage buildVerificationEmailMessage(
        String email,
        String verificationCode,
        EmailTemplate template
    ) {
        String subject = replaceVerificationToken(template.Subject, verificationCode);
        String textBody = replaceVerificationToken(template.Body, verificationCode);
        String htmlBody = replaceVerificationToken(template.HtmlValue, verificationCode);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ email.trim() });

        if (String.isNotBlank(subject)) {
            msg.setSubject(subject);
        }

        // Prefer HTML body when present; otherwise send plain text.
        if (String.isNotBlank(htmlBody)) {
            msg.setHtmlBody(htmlBody);
        } else {
            msg.setPlainTextBody(textBody);
        }

        return msg;
    }

    /**
     * @description Replaces the verification token in a template string if present.
     * @param source           Template text (may be null or blank).
     * @param verificationCode Verification code to inject.
     * @return String with token replaced, or original value when blank.
     */
    private static String replaceVerificationToken(String source, String verificationCode) {
        if (String.isBlank(source)) {
            return source;
        }
        return source.replace('{{{VerificationCode}}}', verificationCode);
    }

    // ----------------------------------------------------------------------
    // Public API – Create Lead and send welcome email (template only)
    // ----------------------------------------------------------------------

    /**
     * @description Creates a Lead record from the payload and sends a welcome email
     * using the configured welcome template.
     * @param payload Map containing firstName, lastName, email, phone.
     * @return Id of the created Lead.
     */
    @AuraEnabled
    public static Id registerLead(Map<String, Object> payload) {
        validatePayload(payload);

        String firstName = (String)payload.get('firstName');
        String lastName  = (String)payload.get('lastName');
        String email     = (String)payload.get('email');
        String phone     = (String)payload.get('phone');

        validateNameFields(firstName, lastName);
        validateEmail(email);

        Lead leadToInsert = buildLead(firstName, lastName, email, phone);

        assertCanCreateLead();
        // Insert in system mode so guest can create Lead (with explicit CRUD check above)
        Database.insert(leadToInsert, AccessLevel.SYSTEM_MODE);

        sendWelcomeEmailSafely(leadToInsert);
        return leadToInsert.Id;
    }

    /**
     * @description Validates that payload is not null or empty.
     * @param payload Payload from LWC.
     */
    private static void validatePayload(Map<String, Object> payload) {
        if (payload == null || payload.isEmpty()) {
            throw new AuraHandledException('Registration payload cannot be empty.');
        }
    }

    /**
     * @description Validates that first and last name are provided.
     * @param firstName Lead first name.
     * @param lastName  Lead last name.
     */
    private static void validateNameFields(String firstName, String lastName) {
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw new AuraHandledException('First Name and Last Name are required.');
        }
    }

    /**
     * @description Builds a Lead instance from provided fields.
     * @param firstName Lead first name.
     * @param lastName  Lead last name.
     * @param email     Lead email.
     * @param phone     Lead phone.
     * @return Lead record (not yet inserted).
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Lead buildLead(String firstName,String lastName,String email,String phone)
    {
        return new Lead(
            FirstName = firstName != null ? firstName.trim() : null,
            LastName  = lastName != null ? lastName.trim() : null,
            Email     = email != null ? email.trim() : null,
            Phone     = phone
        );
    }

    /**
     * @description Sends welcome email and swallows any exception (email failure
     * should not block registration).
     * @param leadRecord Inserted Lead record.
     */
    private static void sendWelcomeEmailSafely(Lead leadRecord) {
        try {
            sendWelcomeEmail(leadRecord);
        } catch (Exception ex) {
            System.debug('Custom Exception occurred: ' + ex.getMessage());
            // Intentionally ignore email failure – registration succeeded.
        }
    }

    // ----------------------------------------------------------------------
    // Private – Welcome email using template (DeveloperName from label)
    // ----------------------------------------------------------------------

    /**
     * @description Sends a welcome email to the provided Lead using the welcome template.
     * @param leadRecord Lead that will receive the email.
     */
    private static void sendWelcomeEmail(Lead leadRecord) {
        if (leadRecord == null || leadRecord.Id == null || String.isBlank(leadRecord.Email)) {
            return;
        }

        Id templateId = getWelcomeTemplateId();
        if (templateId == null) {
            return;
        }

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setTargetObjectId(leadRecord.Id);
        msg.setTemplateId(templateId);
        msg.setSaveAsActivity(true);

        setOrgWideAddressForGuest(msg);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    // ----------------------------------------------------------------------
    // Helpers – Validation, CRUD, and configuration
    // ----------------------------------------------------------------------

    /**
     * @description Validates email format (very basic check).
     * @param email Email address.
     */
    private static void validateEmail(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email is required.');
        }
        String trimmed = email.trim();
        if (!trimmed.contains('@') || !trimmed.contains('.')) {
            throw new AuraHandledException('Please provide a valid email address.');
        }
    }

    /**
     * @description Ensures the running user has create permission on Lead.
     */
    private static void assertCanCreateLead() {
        if (!Schema.sObjectType.Lead.isCreateable()) {
            throw new AuraHandledException(
                'You do not have permission to create Lead records.'
            );
        }
    }

    /**
     * @description Returns the welcome email template Id configured via
     * custom label Registration_Welcome_Template_DevName.
     * @return Id of welcome email template, or null if not found.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static Id getWelcomeTemplateId() {
        if (cachedWelcomeTemplateId != null) {
            return cachedWelcomeTemplateId;
        }

        String devName = System.Label.Registration_Welcome_Template_DevName;
        if (String.isBlank(devName)) {
            return null;
        }

        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate
            WHERE DeveloperName = :devName LIMIT 1];

        if (!templates.isEmpty()) {
            cachedWelcomeTemplateId = templates[0].Id;
        }
        return cachedWelcomeTemplateId;
    }

    /**
     * @description Returns the verification email template configured via
     * custom label Registration_Verification_Template_DevName.
     * @return EmailTemplate instance or null if not found.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static EmailTemplate getVerificationTemplate() {
        if (cachedVerificationTemplate != null) {
            return cachedVerificationTemplate;
        }

        String devName = System.Label.Registration_Verification_Template_DevName;
        if (String.isBlank(devName)) {
            return null;
        }

        List<EmailTemplate> templates = [
            SELECT Id, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :devName
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            return null;
        }

        cachedVerificationTemplate = templates[0];
        return cachedVerificationTemplate;
    }

    /**
     * @description Sets Org-Wide Email Address Id for guest users using
     * custom label Registration_Verification_From_Address.
     * @param msg Email message to update.
     */
    private static void setOrgWideAddressForGuest(Messaging.SingleEmailMessage msg) {
        if (msg == null) {
            return;
        }

        Id orgWideId = getOrgWideEmailAddressId();
        if (orgWideId != null && UserInfo.getUserType() == 'Guest') {
            msg.setOrgWideEmailAddressId(orgWideId);
        }
    }

    /**
     * @description Returns Org-Wide Email Address Id configured in
     * custom label Registration_Verification_From_Address.
     * @return Org-Wide Email Address Id or null when not configured.
     */
    private static Id getOrgWideEmailAddressId() {
        String idStr = System.Label.Registration_Verification_From_Address;
        if (String.isBlank(idStr)) {
            return null;
        }
        return (Id)idStr.trim();
    }
}
