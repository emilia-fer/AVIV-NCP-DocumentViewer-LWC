public with sharing class S3FileCreator {
    @AuraEnabled
    public static Id create(
        String name,
        String type,
        Long size,
        String s3Key,
        String description,
        Integer creationYear,      // for legacy, remove if unused
        Date creationDate,         // <-- New parameter for full date!
        Id accountId,
        Id caseId,
        Id contactId,
        Id opportunityId, 
        String  taskId 
    ) {
        // Validation
        if (String.isBlank(name)) throw new AuraHandledException('File name is required.');
        if (String.isBlank(type)) throw new AuraHandledException('File type is required.');
        if (size == null || size < 0) throw new AuraHandledException('File size must be positive.');
        if (creationDate == null) throw new AuraHandledException('Creation date is required.');

        S3_File__c file = new S3_File__c(
            Name              = name,
            Type__c           = type,
            Size__c           = size,
            S3_Key__c         = s3Key,
            Description__c    = description,
            Creation_Year__c  = creationYear,      // Optional/legacy
            Creation_Date__c  = creationDate,      // <-- Set the full date here
            Account_ID__c     = accountId,
            Case_ID__c        = caseId,
            Contact_ID__c     = contactId,
            Opportunity_ID__c = opportunityId, 
            Task_ID__c        = taskId
        );
        insert file;
        return file.Id;
    }
}