/************************************************************************************
* File Name       : CaseInquiry_API_Test
* Author          : DICUSSION
* Date            : 2026-11-10
* Description     : CaseInquiry_API 테스트 클래스
*************************************************************************************/
@IsTest
private class CaseInquiry_API_Test {

    private static final String TEST_USERNAME = 'test_customer_001';

    @TestSetup
    static void setup() {
        Case c1 = new Case(Subject = 'Test Case 1', Status = 'New', Origin = 'Web', username__c = TEST_USERNAME);
        Case c2 = new Case(Subject = 'Test Case 2', Status = 'New', Origin = 'Web', username__c = TEST_USERNAME);
        Case c3 = new Case(Subject = 'Other Case',  Status = 'New', Origin = 'Web', username__c = 'other_customer');
        insert new List<Case>{ c1, c2, c3 };

        ContentVersion cv = new ContentVersion(
            Title                   = 'TestFile',
            PathOnClient            = 'TestFile.pdf',
            VersionData             = Blob.valueOf('test file content'),
            FirstPublishLocationId  = c1.Id
        );
        insert cv;
    }

    private static Map<String, Object> callApi(String username) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/api/v1/cases';
        req.httpMethod = 'GET';
        if (username != null) req.addParameter('username', username);
        RestContext.request  = req;
        RestContext.response = new RestResponse();

        CaseInquiry_API.getCases();

        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @IsTest
    static void testGetCasesWithFiles() {
        Test.startTest();
        Map<String, Object> body = callApi(TEST_USERNAME);
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, body.get('success'));
        System.assertEquals(2, body.get('totalSize'));

        Integer fileCount = 0;
        for (Object o : (List<Object>) body.get('cases')) {
            Map<String, Object> c = (Map<String, Object>) o;
            System.assert(c.containsKey('Id'));
            System.assert(c.containsKey('CaseNumber'));
            System.assertEquals('Assigned', c.get('Status'), 'New는 Assigned로 변환되어야 함');
            System.assert(!c.containsKey('username__c'), '커스텀 필드는 반환하지 않아야 함');
            for (Object fo : (List<Object>) c.get('files')) {
                Map<String, Object> f = (Map<String, Object>) fo;
                System.assertEquals('TestFile', f.get('fileName'));
                System.assertEquals('pdf', f.get('fileExtension'));
                System.assert((Integer) f.get('fileSize') > 0);
                System.assertNotEquals(null, f.get('createdDate'));
                fileCount++;
            }
        }
        System.assertEquals(1, fileCount);
    }

    @IsTest
    static void testConvertStatus() {
        System.assertEquals('Closed',   CaseInquiry_API.convertStatus('Resolved'));
        System.assertEquals('Closed',   CaseInquiry_API.convertStatus('Closed'));
        System.assertEquals('Assigned', CaseInquiry_API.convertStatus('New'));
        System.assertEquals('Assigned', CaseInquiry_API.convertStatus('Assigned'));
        System.assertEquals('Assigned', CaseInquiry_API.convertStatus('In Progress'));
        System.assertEquals('Assigned', CaseInquiry_API.convertStatus('Need Info'));
        System.assertEquals('Assigned', CaseInquiry_API.convertStatus('Escalation'));
        System.assertEquals('Other',    CaseInquiry_API.convertStatus('Other'));
        System.assertEquals(null,       CaseInquiry_API.convertStatus(null));
    }

    @IsTest
    static void testNoCases() {
        Map<String, Object> body = callApi('not_exist_customer');
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(true, body.get('success'));
        System.assertEquals(0, body.get('totalSize'));
    }

    @IsTest
    static void testMissingUsername() {
        Map<String, Object> body = callApi(null);
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, body.get('success'));
    }
}
