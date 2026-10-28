/************************************************************************************
* File Name         : ctrlSendMarketingCloudAPI_scTest
* Modify Author     : John
* Modify Date       : 2024-07-08
* Description       : Test setting schedule to send data to Salesforce Marketing Cloud
*************************************************************************************/
@isTest
public with sharing class ctrlSendMarketingCloudAPI_scTest {
    private static final Integer RECORD_COUNT = 10;
    private static final String CLIENT_SECRET = 'testClientSecret';

    @TestSetup
    static void makeData(){
        // requestAccessToken() 에서 사용하는 Custom Setting
        // Secret_Code__c 는 Core_MCE 키로 암호화된 값이어야 decrypt() 를 통과하여 토큰 요청 로직까지 커버됨
        // (Batch 도 Core_MCE 의 endpoint__c / authURL__c 를 사용하므로 실제 메타데이터 기준으로 암호화)
        insert new MCE_Rotate_Secret_Code__c(
            Name           = 'Delete Contact Integration',
            Secret_Key__c  = 'testClientId',
            Secret_Code__c = ctrlAesCipher.encrypt(CLIENT_SECRET)
        );

        List<Delete_Contact_List__c> items = new List<Delete_Contact_List__c>();
        for(Integer i = 0; i < RECORD_COUNT; i++){
            items.add(new Delete_Contact_List__c(
                Contact_ID__c = 'Test contact delete ' + i,
                Email__c      = 'test' + i + '@example.com',
                SendYN__c     = false
            ));
        }
        insert items;
    }

    @isTest
    static void testSchedule() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(true));

        Test.startTest();
        String jobId = System.schedule('ctrlSendMarketingCloudAPI_sc Test Job', '0 30 * * * ?', new ctrlSendMarketingCloudAPI_sc());
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 30 * * * ?', ct.CronExpression, 'expecting cron expression to match');

        List<AsyncApexJob> jobsScheduled = [SELECT Id, ApexClass.Name FROM AsyncApexJob WHERE JobType = 'ScheduledApex'];
        System.assertEquals(1, jobsScheduled.size(), 'expecting one scheduled job');
        System.assertEquals('ctrlSendMarketingCloudAPI_sc', jobsScheduled[0].ApexClass.Name, 'expecting specific scheduled job');
    }

    @isTest
    static void testScheduleExecuteDirectly() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(true));

        Test.startTest();
        // execute() 를 직접 호출하여 Batch 가 enqueue 되는지 확인
        new ctrlSendMarketingCloudAPI_sc().execute(null);
        Test.stopTest();

        List<AsyncApexJob> batchJobs = [SELECT Id FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'ctrlSendMarketingCloudAPI_ba'];
        System.assertEquals(1, batchJobs.size(), 'expecting one batch job');
    }

    @isTest
    static void testBatchProcess(){
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(true));

        Test.startTest();
        Database.executeBatch(new ctrlSendMarketingCloudAPI_ba(), RECORD_COUNT);
        Test.stopTest();

        Integer sentCount = [SELECT COUNT() FROM Delete_Contact_List__c WHERE SendYN__c = true];
        System.assertEquals(RECORD_COUNT, sentCount, 'all records should be flagged as sent');
    }

    @isTest
    static void testBatchProcessTokenError(){
        // 토큰 응답에 access_token 이 없는 경우 -> requestAccessToken() 의 catch 블록 커버
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(false));

        Test.startTest();
        Database.executeBatch(new ctrlSendMarketingCloudAPI_ba(), RECORD_COUNT);
        Test.stopTest();

        // 토큰 오류는 내부에서 catch 되므로 Batch 는 계속 진행됨
        Integer sentCount = [SELECT COUNT() FROM Delete_Contact_List__c WHERE SendYN__c = true];
        System.assertEquals(RECORD_COUNT, sentCount, 'batch should still flag records when token request fails');
    }

    @isTest
    static void testBatchNoTarget(){
        // 대상 데이터가 없는 경우
        List<Delete_Contact_List__c> items = [SELECT Id, SendYN__c FROM Delete_Contact_List__c];
        for(Delete_Contact_List__c item : items) item.SendYN__c = true;
        update items;

        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(true));

        Test.startTest();
        Database.executeBatch(new ctrlSendMarketingCloudAPI_ba(), RECORD_COUNT);
        Test.stopTest();

        Integer notSentCount = [SELECT COUNT() FROM Delete_Contact_List__c WHERE SendYN__c = false];
        System.assertEquals(0, notSentCount, 'no records should remain unsent');
    }

    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private Boolean isSuccess;
        private String deleteResponse = '{"success":"true"}';
        private String accessTokenRes = '{"access_token":"c3129196-ad93-4bb8-bc3a-73528e551dfd","token_type":"bearer","expires_in":86399,"scope":"read"}';
        private String accessTokenErr = '{"error":"invalid_client","error_description":"Client authentication failed."}';

        public MockHttpResponseGenerator(Boolean isSuccess){
            this.isSuccess = isSuccess;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            String endpoint = request.getEndpoint();
            if(endpoint.contains('delete?type=keys')){
                response.setStatusCode(200);
                response.setBody(deleteResponse);
            } else if(endpoint.contains('/token')){
                response.setStatusCode(isSuccess ? 200 : 401);
                response.setBody(isSuccess ? accessTokenRes : accessTokenErr);
            } else {
                response.setStatusCode(404);
                response.setBody('{}');
            }
            return response;
        }
    }
}
