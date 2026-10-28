/**
 * Created by jc on 2021-10-27
 */
@IsTest
public without sharing class ctrlMarketingCloudTest {
    private static final Integer RECORD_COUNT = 10;
    private static final String CLIENT_SECRET = 'testClientSecret';

    @TestSetup
    static void makeData() {
        // ctrlMarketingCloudContactDeleteBatch.execute() 에서 사용하는 Custom Setting
        // Secret_Code__c 는 Core_MCE 키로 암호화된 값이어야 decrypt() 를 통과함
        insert new MCE_Rotate_Secret_Code__c(
            Name           = 'Delete Contact Integration',
            Secret_Key__c  = 'testClientId',
            Secret_Code__c = ctrlAesCipher.encrypt(CLIENT_SECRET)
        );

        List<Delete_Contact_List__c> deleteContacts = new List<Delete_Contact_List__c>();
        for (Integer i = 0; i < RECORD_COUNT; i++) {
            deleteContacts.add(new Delete_Contact_List__c(
                Contact_ID__c  = 'TestContact' + i,
                Email__c       = 'test' + i + '@testing.com',
                Seller_ID__c   = 'Test' + i,
                SendYN__c      = false,
                isProcessed__c = false
            ));
        }
        insert deleteContacts;
    }

    @IsTest
    static void testBehavior() {
        StaticResourceCalloutMock mock = new StaticResourceCalloutMock();
        mock.setStaticResource('ctrlMarketingCloud');
        mock.setStatusCode(200);
        mock.setHeader('Content-Type', 'application/json');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<Contact> testContacts = new List<Contact>();
        testContacts.add(new Contact(Email = 'test@testing.com', Seller_ID__c = 'Test123456'));
        testContacts.add(new Contact(Email = 'test22@testing.com', Seller_ID__c = 'Test78901'));
        ctrlMarketingCloud.contactsDelete(testContacts);
        Test.stopTest();
    }

    @IsTest
    static void testScheduler() {
        Test.setMock(HttpCalloutMock.class, new TokenMock());

        Test.startTest();
        String jobId = System.schedule('MarketingCloudContactDelete', '0 0 3 * * ?', new ctrlMarketingCloudContactDeleteScheduler());
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 3 * * ?', ct.CronExpression, 'expecting cron expression to match');
    }

    @IsTest
    static void testBatch() {
        Test.setMock(HttpCalloutMock.class, new TokenMock());

        Test.startTest();
        Database.executeBatch(new ctrlMarketingCloudContactDeleteBatch(), 25);
        Test.stopTest();

        Integer processedCount = [SELECT COUNT() FROM Delete_Contact_List__c WHERE isProcessed__c = true];
        System.assertEquals(RECORD_COUNT, processedCount, 'all records should be flagged as processed');
    }

    private class TokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            if (req.getEndpoint().endsWith('/v2/token')) {
                res.setBody('{"access_token":"c3129196-ad93-4bb8-bc3a-73528e551dfd","token_type":"bearer","expires_in":1079}');
            } else {
                res.setBody('{"operationInitiated":true}');
            }
            return res;
        }
    }
}
