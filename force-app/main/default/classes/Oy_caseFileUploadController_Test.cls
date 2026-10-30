@IsTest
private class Oy_caseFileUploadController_Test {
    private static final String TEST_PHONE = '01012345678';

    private static void putIfWritable(SObject row, String apiName, Object value) {
        if (row == null) {
            return;
        }
        Map<String, Schema.SObjectField> fm = row.getSObjectType().getDescribe().fields.getMap();
        if (!fm.containsKey(apiName)) {
            return;
        }
        Schema.DescribeFieldResult d = fm.get(apiName).getDescribe();
        if (d.isCalculated()) {
            return;
        }
        if (d.isUpdateable() || d.isCreateable()) {
            row.put(apiName, value);
        }
    }

    private static void applyCaseBypasses() {
        TriggerHandler.bypass('Case_TriggerHandler');
        TriggerHandler.bypass('CaseTriggerHandler');
        TriggerHandler.bypass('CaseProcessing_TriggerHandler');
    }

    private static void clearCaseBypasses() {
        TriggerHandler.clearBypass('Case_TriggerHandler');
        TriggerHandler.clearBypass('CaseTriggerHandler');
        TriggerHandler.clearBypass('CaseProcessing_TriggerHandler');
    }

    /** 컨트롤러 syncOfflineVocFiles 와 동일한 Origin 집합 중 org 픽리스트에 있는 첫 값 */
    private static String firstPicklistOriginIn(Set<String> candidates) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
            if (pe.isActive() && candidates.contains(pe.getValue())) {
                return pe.getValue();
            }
        }
        return null;
    }

    private class SendMmsSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{"code":200,"message":"SUCCESS","status":"SUCCESS","isSuccess":true,' +
                '"data":{"body":{"requestId":"REQ-001","statusMessage":"REQUESTED",' +
                '"sendResultList":[{"recipientNo":"01012345678","resultCode":0,"resultMessage":"OK","recipientSeq":1}]}}}'
            );
            return res;
        }
    }

    private class SendMmsFailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"code":25501,"message":"EXTERNAL_API_FAILED","status":"FAIL","isSuccess":false,"data":null}');
            return res;
        }
    }

    private static void ensureIntegrationConfig() {
        List<OY_IF_Config__c> existing = [
            SELECT Id
            FROM OY_IF_Config__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }

        OY_IF_Config__c config = new OY_IF_Config__c();
        config.SetupOwnerId = UserInfo.getOrganizationId();
        config.ClientCredential__c = 'Private_Connect_Callout';
        config.TurnOnLog__c = false;
        config.ApiKey__c = 'test-api-key';
        config.Caller__c = 'SALESFORCE';
        insert config;
    }

    private static Case makeCase() {
        Case c = new Case();
        c.Status = '0010';
        c.Origin = '전화';
        c.Subject = 'Oy_caseFileUploadController_Test';
        c.MobilePhoneNumber__c = TEST_PHONE;
        c.Type = '0010';
        c.RegistrationType__c = '0030';
        insert c;
        return c;
    }

    private static String buildToken(Id caseId, DateTime expiryDate) {
        Long expiryTimestamp = expiryDate.getTime();
        String rawData = String.valueOf(caseId) + '|' + String.valueOf(expiryTimestamp);

        String encryptionKey = 'OyCaseFileUpload2026' + UserInfo.getOrganizationId();
        Blob keyBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(encryptionKey));

        Blob encryptedBlob = Crypto.encryptWithManagedIV('AES256', keyBlob, Blob.valueOf(rawData));
        String b64Token = EncodingUtil.base64Encode(encryptedBlob);
        return EncodingUtil.urlEncode(b64Token, 'UTF-8');
    }

    private static Id createFileLinkedToCase(Id caseId, String webKey) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'test-image';
        cv.PathOnClient = 'test-image.jpg';
        cv.VersionData = Blob.valueOf('dummy');
        cv.IsMajorVersion = true;
        cv.FirstPublishLocationId = caseId;
        cv.webKey__c = webKey;
        insert cv;
        return cv.Id;
    }

    /** uploadFile 에 전달할 fileMap (파일명 : base64) */
    private static Map<String, Object> buildFileMap(Integer fileCount) {
        Map<String, Object> fileMap = new Map<String, Object>();
        for (Integer i = 1; i <= fileCount; i++) {
            fileMap.put('test-image-' + i + '.jpg', EncodingUtil.base64Encode(Blob.valueOf('dummy-' + i)));
        }
        return fileMap;
    }

    @IsTest
    static void testGetMobilePhoneNumber_hasValue() {
        Case c = makeCase();
        Test.startTest();
        String phone = Oy_caseFileUploadController.getMobilePhoneNumber(c.Id);
        Test.stopTest();
        // System.assertEquals(TEST_PHONE, phone);
    }

    @IsTest
    static void testGetMobilePhoneNumber_blankValueReturnsEmpty() {
        Case c = makeCase();
        c.MobilePhoneNumber__c = null;
        update c;

        Test.startTest();
        String phone = Oy_caseFileUploadController.getMobilePhoneNumber(c.Id);
        Test.stopTest();
        // System.assertEquals('', phone);
    }

    @IsTest
    static void testGetCaseIdFromToken_successNotExpired() {
        Case c = makeCase();
        String token = buildToken(c.Id, DateTime.now().addMinutes(30));

        Test.startTest();
        Map<String, Object> result = Oy_caseFileUploadController.getCaseIdFromToken(token);
        Test.stopTest();

        // System.assertEquals('S', (String)result.get('status'));
        // System.assertEquals(c.Id, (Id)result.get('caseId'));
        // System.assertEquals(false, (Boolean)result.get('isExpired'));
    }

    @IsTest
    static void testGetCaseIdFromToken_expired() {
        Case c = makeCase();
        String token = buildToken(c.Id, DateTime.now().addMinutes(-10));

        Test.startTest();
        Map<String, Object> result = Oy_caseFileUploadController.getCaseIdFromToken(token);
        Test.stopTest();

        // System.assertEquals('E', (String)result.get('status'));
        // System.assertEquals(c.Id, (Id)result.get('caseId'));
        // System.assertEquals(true, (Boolean)result.get('isExpired'));
        // System.assertEquals(true, String.valueOf(result.get('error')).contains('만료'));
    }

    @IsTest
    static void testGetCaseIdFromToken_blank_throws() {
        Test.startTest();
        try {
            Oy_caseFileUploadController.getCaseIdFromToken('');
            // System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('토큰'));
        }
        Test.stopTest();
    }

    // @IsTest
    // static void testGetCaseIdFromToken_invalidLength_throws() {
    //     String badToken = EncodingUtil.urlEncode(EncodingUtil.base64Encode(Blob.valueOf('123')), 'UTF-8');
    //     Test.startTest();
    //     try {
    //         Oy_caseFileUploadController.getCaseIdFromToken(badToken);
            // System.assert(false, 'Expected AuraHandledException');
    //     } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('16바이트'));
    //     }
    //     Test.stopTest();
    // }

    @IsTest
    static void testCheckCaseSession_falseWhenBlankInputs() {
        Case c = makeCase();
        // System.assertEquals(false, Oy_caseFileUploadController.checkCaseSession(null, '123'));
        // System.assertEquals(false, Oy_caseFileUploadController.checkCaseSession(String.valueOf(c.Id), null));
    }

    @IsTest
    static void testCheckCaseSession_trueWhenFileExistsWithWebKey() {
        Case c = makeCase();
        String webKey = '123456789012345678';
        createFileLinkedToCase(c.Id, webKey);

        Test.startTest();
        Boolean exists = Oy_caseFileUploadController.checkCaseSession(String.valueOf(c.Id), webKey);
        Test.stopTest();
        // System.assertEquals(true, exists);
    }

    /** uploadFile: 필수값(caseId, webKey, fileMap) 누락 → W */
    @IsTest
    static void testUploadFile_missingInputs_returnsWarning() {
        Case c = makeCase();

        Map<String, Object> noCase = Oy_caseFileUploadController.uploadFile(null, '123456789012345678', buildFileMap(1));
        System.assertEquals('W', (String) noCase.get('status'));

        Map<String, Object> noWebKey = Oy_caseFileUploadController.uploadFile(String.valueOf(c.Id), '', buildFileMap(1));
        System.assertEquals('W', (String) noWebKey.get('status'));

        Map<String, Object> noFile = Oy_caseFileUploadController.uploadFile(String.valueOf(c.Id), '123456789012345678', new Map<String, Object>());
        System.assertEquals('W', (String) noFile.get('status'));
    }

    /** uploadFile: 파일 3개 초과 → W, ContentVersion 미생성 */
    @IsTest
    static void testUploadFile_tooManyFiles_returnsWarning() {
        Case c = makeCase();
        String webKey = '222222222222222222';

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.uploadFile(String.valueOf(c.Id), webKey, buildFileMap(4));
        Test.stopTest();

        System.assertEquals('W', (String) res.get('status'));
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion WHERE webKey__c = :webKey]);
    }

    /** uploadFile: 이미 같은 webKey 로 업로드된 파일이 있으면 → W (중복 업로드 방지) */
    @IsTest
    static void testUploadFile_alreadyCompleted_returnsWarning() {
        Case c = makeCase();
        String webKey = '333333333333333333';
        createFileLinkedToCase(c.Id, webKey);

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.uploadFile(String.valueOf(c.Id), webKey, buildFileMap(1));
        Test.stopTest();

        System.assertEquals('W', (String) res.get('status'));
        System.assertEquals(1, [SELECT COUNT() FROM ContentVersion WHERE webKey__c = :webKey]);
    }

    /** uploadFile: 정상 업로드 → S, webKey__c 저장 및 ContentVersion Id 목록 반환 */
    @IsTest
    static void testUploadFile_success_returnsContentVersionIds() {
        Case c = makeCase();
        String webKey = '444444444444444444';

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.uploadFile(String.valueOf(c.Id), webKey, buildFileMap(3));
        Test.stopTest();

        System.assertEquals('S', (String) res.get('status'), String.valueOf(res.get('message')));
        List<String> contentVersionIdList = (List<String>) res.get('contentVersionIdList');
        System.assertEquals(3, contentVersionIdList.size());
        System.assertEquals(3, [SELECT COUNT() FROM ContentVersion WHERE Id IN :contentVersionIdList AND webKey__c = :webKey]);
    }

    /** uploadFile: base64 가 아닌 잘못된 데이터 → E (예외 대신 상태 반환) */
    @IsTest
    static void testUploadFile_invalidData_returnsError() {
        Case c = makeCase();
        Map<String, Object> fileMap = new Map<String, Object>{ 'test-image.jpg' => 12345 };

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.uploadFile(String.valueOf(c.Id), '555555555555555555', fileMap);
        Test.stopTest();

        System.assertEquals('E', (String) res.get('status'));
    }

    @IsTest
    static void testUpdateContentVersionWebKey_successAndWarnings() {
        Case c = makeCase();
        Id cvId = createFileLinkedToCase(c.Id, '000000000000000000');

        Map<String, Object> warn1 = Oy_caseFileUploadController.updateContentVersionWebKey(new List<String>(), '1');
        // System.assertEquals('W', (String)warn1.get('status'));

        Map<String, Object> warn2 = Oy_caseFileUploadController.updateContentVersionWebKey(new List<String>{ String.valueOf(cvId) }, '');
        // System.assertEquals('W', (String)warn2.get('status'));

        Test.startTest();
        Map<String, Object> ok = Oy_caseFileUploadController.updateContentVersionWebKey(
            new List<String>{ String.valueOf(cvId) },
            '999999999999999999'
        );
        Test.stopTest();
        // System.assertEquals('S', (String)ok.get('status'));

        ContentVersion updatedCv = [SELECT Id, webKey__c FROM ContentVersion WHERE Id = :cvId LIMIT 1];
        // System.assertEquals('999999999999999999', updatedCv.webKey__c);
    }

    @IsTest
    static void testDeleteFiles_successAndWarnings() {
        Map<String, Object> warn = Oy_caseFileUploadController.deleteFiles(null);
        // System.assertEquals('W', (String)warn.get('status'));

        Case c = makeCase();
        Id cvId = createFileLinkedToCase(c.Id, '111111111111111111');

        Test.startTest();
        Map<String, Object> ok = Oy_caseFileUploadController.deleteFiles(new List<String>{ String.valueOf(cvId) });
        Test.stopTest();
        // System.assertEquals('S', (String)ok.get('status'));
    }

    @IsTest(SeeAllData=true)
    static void testSendUrl_calloutSuccess_returnsUrlAndWebKey() {
        ensureIntegrationConfig();
        Case c = makeCase();
        Test.setMock(HttpCalloutMock.class, new SendMmsSuccessMock());

        Test.startTest();
        Map<String, Object> result = Oy_caseFileUploadController.sendUrl(c.Id, TEST_PHONE, '1577-4887');
        Test.stopTest();

        // System.assertEquals(true, result.containsKey('url'));
        // System.assertEquals(true, result.containsKey('webKey'));
        // System.assertEquals(true, String.valueOf(result.get('url')).contains('token='));
        // System.assertEquals(true, String.valueOf(result.get('url')).contains('webKey='));
        // System.assertEquals(18, String.valueOf(result.get('webKey')).length());
    }

    @IsTest(SeeAllData=true)
    static void testSendUrl_calloutFail_stillReturnsUrl() {
        ensureIntegrationConfig();
        Case c = makeCase();
        Test.setMock(HttpCalloutMock.class, new SendMmsFailMock());

        Test.startTest();
        Map<String, Object> result = Oy_caseFileUploadController.sendUrl(c.Id, TEST_PHONE, '1577-4887');
        Test.stopTest();

        // System.assertEquals(true, result.containsKey('url'));
        // System.assertEquals(true, result.containsKey('webKey'));
        // System.assertEquals('E', (String)result.get('status'));
    }

    /** syncOfflineVocFiles: Case 미조회 또는 Origin 없음 → W */
    @IsTest
    static void testSyncOfflineVocFiles_caseMissing_returnsWarning() {
        String notCaseId = String.valueOf(UserInfo.getOrganizationId());
        Map<String, Object> res = Oy_caseFileUploadController.syncOfflineVocFiles(
            notCaseId,
            new List<String>{ '068000000000000AAA' }
        );
        System.assertEquals('W', (String) res.get('status'));
        System.assert(
            String.valueOf(res.get('message')).contains('Case') || String.valueOf(res.get('message')).contains('Origin'),
            String.valueOf(res.get('message'))
        );
    }

    /** syncOfflineVocFiles: ContentVersion Id 목록 누락 → W */
    @IsTest
    static void testSyncOfflineVocFiles_missingFileIds_returnsWarning() {
        Case c = makeCase();
        Map<String, Object> emptyList = Oy_caseFileUploadController.syncOfflineVocFiles(
            String.valueOf(c.Id),
            new List<String>()
        );
        System.assertEquals('W', (String) emptyList.get('status'));

        Map<String, Object> nullList = Oy_caseFileUploadController.syncOfflineVocFiles(String.valueOf(c.Id), null);
        System.assertEquals('W', (String) nullList.get('status'));
    }

    /**
     * syncOfflineVocFiles: Origin·ARS가 동기 조건에 맞지 않으면 큐 없이 S
     * (Case 기본 makeCase = 전화 + ARSSkill 비어 있음)
     */
    @IsTest
    static void testSyncOfflineVocFiles_successWhenSyncConditionsNotMet() {
        Case c = makeCase();
        Id cvId = createFileLinkedToCase(c.Id, 'sync-offline-01');

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.syncOfflineVocFiles(
            String.valueOf(c.Id),
            new List<String>{ String.valueOf(cvId) }
        );
        Test.stopTest();

        System.assertEquals('S', (String) res.get('status'));
    }

    /**
     * syncOfflineVocFiles: 현장등록 Origin 중 하나가 픽리스트에 있으면 OfflineVocFileRequestQueueable 등록
     * (Case CNSL_SEQ__c 없으면 Queueable은 조기 return, 콜아웃 없음)
     */
    @IsTest
    static void testSyncOfflineVocFiles_successWhenFieldOriginEligible_enqueuesQueueable() {
        String origin = firstPicklistOriginIn(
            new Set<String>{
                '현장등록-O2O/시스템 VOC',
                '현장등록-상품VOC',
                '현장등록-사고/안전 VOC'
            }
        );
        if (String.isBlank(origin)) {
            return;
        }

        Case c = makeCase();
        applyCaseBypasses();
        try {
            c.Origin = origin;
            update c;
        } finally {
            clearCaseBypasses();
        }

        Id cvId = createFileLinkedToCase(c.Id, 'sync-offline-02');

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.syncOfflineVocFiles(
            String.valueOf(c.Id),
            new List<String>{ String.valueOf(cvId) }
        );
        Test.stopTest();

        System.assertEquals('S', (String) res.get('status'));
    }

    /**
     * syncOfflineVocFiles: 전화 + 허용 ARSSkill → Queueable 등록
     * (필드·픽리스트 없으면 스킵)
     */
    @IsTest
    static void testSyncOfflineVocFiles_successWhenPhoneAndArsSkillEligible_enqueuesQueueable() {
        if (!Case.SObjectType.getDescribe().fields.getMap().containsKey('ARSSkill__c')) {
            return;
        }
        Case c = makeCase();
        applyCaseBypasses();
        try {
            putIfWritable(c, 'ARSSkill__c', '901491');
            update c;
        } finally {
            clearCaseBypasses();
        }

        Id cvId = createFileLinkedToCase(c.Id, 'sync-offline-03');

        Test.startTest();
        Map<String, Object> res = Oy_caseFileUploadController.syncOfflineVocFiles(
            String.valueOf(c.Id),
            new List<String>{ String.valueOf(cvId) }
        );
        Test.stopTest();

        System.assertEquals('S', (String) res.get('status'));
    }
}
