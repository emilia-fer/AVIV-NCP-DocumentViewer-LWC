@IsTest
public class S3FileCreatorTest {
    @IsTest
    static void testCreate_HappyPath() {
        // Create dummy related records
        Account a = new Account(Name='Test Account');
        insert a;
        Case c = new Case(Status='New', Origin='Web', Subject='Test');
        insert c;
        Contact ct = new Contact(LastName='Contact', AccountId=a.Id);
        insert ct;
        Opportunity o = new Opportunity(Name='Opp', StageName='Prospecting', CloseDate=Date.today());
        insert o;

        // Call creator
        Id fileId = S3FileCreator.create(
            'TestFile.txt',
            'text/plain',
            12345L,
            'files/TestFile.txt',
            'My description',
            2024,
            Date.today(),
            a.Id,
            c.Id,
            ct.Id,
            o.Id,
            null
        );
        System.debug('Created fileId: ' + fileId);

        // Assert correctness
        S3_File__c created = [
            SELECT Name, Type__c, Size__c, S3_Key__c, Description__c,
                   Creation_Year__c, Creation_Date__c,
                   Account_ID__c, Case_ID__c, Contact_ID__c, Opportunity_ID__c,
                   Task_ID__c
            FROM S3_File__c WHERE Id = :fileId
        ];
        System.assertEquals('TestFile.txt', created.Name);
        System.assertEquals('text/plain', created.Type__c);
        System.assertEquals(12345L, created.Size__c);
        System.assertEquals('files/TestFile.txt', created.S3_Key__c);
        System.assertEquals('My description', created.Description__c);
        System.assertEquals(2024, created.Creation_Year__c);
        System.assertEquals(Date.today(), created.Creation_Date__c);
        System.assertEquals(a.Id, created.Account_ID__c);
        System.assertEquals(c.Id, created.Case_ID__c);
        System.assertEquals(ct.Id, created.Contact_ID__c);
        System.assertEquals(o.Id, created.Opportunity_ID__c);
        System.assertEquals(null, created.Task_ID__c);
    }

    @IsTest
    static void testCreate_ValidationErrors() {
        // Name missing
        Boolean thrown = false;
        try {
            S3FileCreator.create(
                null,
                'type',
                1L,
                'key',
                'desc',
                2024,
                Date.today(),
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            thrown = true;
            System.debug('Missing name error: ' + e.getMessage());
        }
        System.assert(thrown, 'Should throw for missing name');

        // Type missing
        thrown = false;
        try {
            S3FileCreator.create(
                'Name',
                null,
                1L,
                'key',
                'desc',
                2024,
                Date.today(),
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            thrown = true;
            System.debug('Missing type error: ' + e.getMessage());
        }
        System.assert(thrown, 'Should throw for missing type');

        // Negative size
        thrown = false;
        try {
            S3FileCreator.create(
                'Name',
                'type',
                -100L,
                'key',
                'desc',
                2024,
                Date.today(),
                null,
                null,
                null,
                null,
                null
            );
        } catch (AuraHandledException e) {
            thrown = true;
            System.debug('Negative size error: ' + e.getMessage());
        }
        System.assert(thrown, 'Should throw for negative size');
    }
}