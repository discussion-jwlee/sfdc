/**
 * @description       :
 * @author            : donghyun.kim2@cj.net.partial
 * @group             :
 * @last modified on  : 2026-10-30
 * @last modified by  : donghyun.kim2@cj.net.partial
**/
public without sharing class Oy_caseFileUploadController {
    // private static String URL = 'https://data-platform-6962--partial.sandbox.my.site.com/oliveyoungGuest/s/';
    private static String ENCRYPTION_KEY_BASE = 'OyCaseFileUpload2026'; // 암호화 키 베이스 (조직 ID와 결합하여 사용)
    private static String encryptionKeyCache; // 키 캐시
    private static final Integer MAX_UPLOAD_FILE_COUNT = 3; // 업로드 가능 최대 파일 수

    public Oy_caseFileUploadController() {

    }

    /**
     * 암호화 키를 생성합니다.
     * 조직 ID를 기반으로 일관된 키를 생성하여 동일한 조직에서는 항상 같은 키가 생성됩니다.
     * @return String 암호화 키 베이스 문자열 (SHA-256 해시 전 원본)
     */
    private static String getEncryptionKey() {
        if (encryptionKeyCache == null) {
            try {
                // 조직 ID를 가져와서 키 생성 (조직마다 고유한 키 생성)
                String orgId = UserInfo.getOrganizationId();
                encryptionKeyCache = ENCRYPTION_KEY_BASE + orgId;
            } catch (Exception e) {
                System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
                // 폴백: 기본 키 사용
                // encryptionKeyCache = ENCRYPTION_KEY_BASE + 'DefaultKey2026';
            }
        }
        return encryptionKeyCache;
    }

    @AuraEnabled
    public static String getMobilePhoneNumber(String recordId){
        try {
            Case c = [SELECT Id, MobilePhoneNumber__c FROM Case WHERE Id = :recordId LIMIT 1];
            if(String.isBlank(c.MobilePhoneNumber__c)) {
                return '';
            }
            return c.MobilePhoneNumber__c;
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('[' + e.getLineNumber() + ']' + e.getMessage());
        }
    }

    /**
     * URL 생성
     * @param recordId Case ID
     * @return Map<String, Object> URL 및 상태 정보
     */
    @AuraEnabled
    public static Map<String, Object> sendUrl(String recordId, String phoneNumber, String sendNo){
        Map<String, Object> returnMap = new Map<String, Object>();

        try {
            if (String.isBlank(recordId)) {
                returnMap.put('status', 'W');
                returnMap.put('message', '필수 정보가 누락되었습니다.');
                return returnMap;
            }

            // 사이트 URL 조회는 배포/테스트 환경에 따라 레코드가 없을 수 있으므로, 실패 시 폴백 URL로 진행
            String guestSiteUrl = '';
            try {
                Site guestSite = [
                    SELECT Id
                    FROM Site
                    WHERE MasterLabel = 'oliveyoungGuest'
                    AND SiteType = 'ChatterNetworkPicasso'
                    LIMIT 1
                ];
                guestSiteUrl = [
                    SELECT SecureUrl
                    FROM SiteDetail
                    WHERE DurableId = :guestSite.Id
                    LIMIT 1
                ].SecureUrl;
            } catch (Exception siteEx) {
                System.debug('Guest Site URL 조회 실패(폴백 사용): ' + siteEx.getMessage());
                guestSiteUrl = URL.getOrgDomainUrl().toExternalForm();
            }

            if (String.isBlank(guestSiteUrl)) {
                guestSiteUrl = URL.getOrgDomainUrl().toExternalForm();
            }

            System.debug('guestSiteUrl :::' + guestSiteUrl);
            // Case c = [SELECT Id, MobilePhoneNumber__c FROM Case WHERE Id = :recordId LIMIT 1];
            // String phoneNumber = (c.MobilePhoneNumber__c != null) ? String.valueOf(c.MobilePhoneNumber__c).replace('-', '') : null;
            // System.debug('phoneNumber :::' + phoneNumber);

            // if(String.isBlank(phoneNumber)) {
            //     returnMap.put('status', 'E');
            //     returnMap.put('message', '고객의 전화번호가 없습니다.');
            //     return returnMap;
            // }
            // System.debug('phoneNumber :::' + phoneNumber);
            // System.debug('recordId :::' + recordId);
            String token = generateToken(recordId);
            String webKey = generateWebKey();
            String url = guestSiteUrl + '?token=' + token + '&webKey=' + webKey;

            // System.debug('url :::' + url);

            // SMS 전송 시도 (실패해도 URL은 반환)
            try {
                OY_IF_CallCampaignService.SendMmsRequest req = new OY_IF_CallCampaignService.SendMmsRequest();
                OY_IF_CallCampaignService.MmsRecipient recipient = new OY_IF_CallCampaignService.MmsRecipient();
                recipient.recipientNo = phoneNumber; // phoneNumber;
                req.title = '[올리브영 고객센터]';

                // UserInfo.getName() 임시 추가.
                req.body =  '안녕하세요. 올리브영 고객센터입니다.' + '\n' +
                            '상세 확인을 위해 아래 링크에서 사진을 첨부해 주세요.' + '\n' +
                            '-첨부 방법: 아래 링크 접속 (최대 3장)' + '\n' +
                            '-유효 기간: 문자 수신 후 24시간 이내' + '\n' +
                            '-링크 바로가기:' + url + '\n' +
                            '24시간이 경과하여 링크가 만료된 경우 1:1문의로 사진을 첨부해 주세요.' + '\n' +
                            '항상 노력하는 올리브영이 되겠습니다. 감사합니다.';
                req.sendNo = sendNo; // 1577-4887, 1533-4887
                req.teams = 'ONLINE_MALL'; // ONLINE_MALL로 사용. [확인 완료]
                req.isTest = false;
                req.recipientList = new List<OY_IF_CallCampaignService.MmsRecipient>{ recipient };
                req.attachedFileIds = new List<Integer>{};

                OY_IF_CallCampaignService.SendMmsResponse res = OY_IF_CallCampaignService.sendMms(req);

                // System.debug('SMS 전송 성공: ' + JSON.serialize(res));

                returnMap.put('status', 'S');
                returnMap.put('message', 'URL 전송 성공');
            } catch (Exception smsException) {
                // SMS 전송 실패해도 URL은 반환 (로깅만 수행)
                System.debug('SMS 전송 실패: [' + smsException.getLineNumber() + ']' + smsException.getMessage() + ' ' + smsException.getStackTraceString());
                // 필요시 추가 로깅 또는 알림 처리
                returnMap.put('status', 'E');
                returnMap.put('message', 'URL 전송 실패: [' + smsException.getLineNumber() + ']' + smsException.getMessage() + ' ' + smsException.getStackTraceString());
            }


            returnMap.put('url', url);
            returnMap.put('webKey', webKey);
            return returnMap;

            // return JSON.serialize(res);
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('[' + e.getLineNumber() + ']' + e.getMessage());
        }
    }

    /**
     * 토큰 생성
     * @param caseId Case ID
     * @return String 토큰
     */
    private static String generateToken(String caseId) {
        try {
            // 1. 만료 시간 설정 (현재 시간 + 10분)
            DateTime expiryDate = DateTime.now().addDays(1);  // URL의 유효기간은 24시간 이내 .addMinutes(1); //
            Long expiryTimestamp = expiryDate.getTime();

            // 2. 암호화할 데이터 조합 (CaseId | 만료시간)
            String rawData = caseId + '|' + expiryTimestamp;
            Blob dataToEncrypt = Blob.valueOf(rawData);

            // 3. 암호화 키 생성 (AES256은 32바이트 키가 필요하므로 SHA-256 해시 사용)
            String encryptionKey = getEncryptionKey();
            Blob keyBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(encryptionKey));

            // 4. AES256 알고리즘으로 암호화
            Blob encryptedBlob = Crypto.encryptWithManagedIV('AES256', keyBlob, dataToEncrypt);

            // 5. Base64 인코딩 (문자열 화)
            String b64Token = EncodingUtil.base64Encode(encryptedBlob);

            // 6. URL Safe 인코딩 (+, /, = 기호가 URL에서 깨지지 않게 변환)
            String token = EncodingUtil.urlEncode(b64Token, 'UTF-8');
            return token;
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            return 'error';
        }
    }

    /**
     * 18자리 숫자 난수 문자열을 생성합니다.
     * @return String 18자리 webKey
     */
    private static String generateWebKey() {
        String webKey = '';
        for (Integer i = 0; i < 18; i++) {
            Integer digit = (Integer)Math.floor(Math.random() * 10);
            webKey += String.valueOf(digit);
        }
        return webKey;
    }

    // 토큰을 복호화하여 유효성을 검증하고 Case ID를 반환합니다.
    @AuraEnabled
    public static Map<String, Object> getCaseIdFromToken(String encodedToken){
        Map<String, Object> returnMap = new Map<String, Object>();
        try {
            // 입력값 검증
            if (String.isBlank(encodedToken)) {
                throw new AuraHandledException('토큰이 제공되지 않았습니다.');
            }

            // 1. URL 디코딩 및 Base64 디코딩
            String decodedToken = EncodingUtil.urlDecode(encodedToken, 'UTF-8');
            decodedToken = decodedToken.replace(' ', '+');

            Blob encryptedData = EncodingUtil.base64Decode(decodedToken);

            // AES256 블록 크기 검증 (16바이트 배수여야 함)
            if (encryptedData.size() == 0 || Math.mod(encryptedData.size(), 16) != 0) {
                throw new AuraHandledException('암호화된 데이터 길이가 올바르지 않습니다. (길이: ' + encryptedData.size() + ', 16바이트 배수여야 함)');
            }

            // 2. 암호화 키 생성 (AES256은 32바이트 키가 필요하므로 SHA-256 해시 사용)
            String encryptionKey = getEncryptionKey();
            Blob keyBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(encryptionKey));

            // 3. 복호화
            Blob decryptedBlob = Crypto.decryptWithManagedIV('AES256', keyBlob, encryptedData);
            String decryptedStr = decryptedBlob.toString();

            if (String.isBlank(decryptedStr)) {
                throw new AuraHandledException('복호화된 데이터가 비어있습니다.');
            }

            // 4. 데이터 분리 (ID | Timestamp)
            String[] parts = decryptedStr.split('\\|');
            Id caseId = (Id)parts[0];
            Long expiryTimestamp = Long.valueOf(parts[1]);

            // 5. 시간 만료 체크
            if (DateTime.now().getTime() > expiryTimestamp) {
                returnMap.put('status', 'E');
                returnMap.put('caseId', caseId);
                returnMap.put('isExpired', true);
                returnMap.put('error', '이 링크는 이미 만료되었습니다.');
                return returnMap;
            }

            returnMap.put('status', 'S');
            returnMap.put('caseId', caseId);
            returnMap.put('isExpired', false);
            return returnMap;
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            // throw new AuraHandledException('유효하지 않은 접근이거나 링크가 손상되었습니다.');
        }
    }

    /**
     * 세션 유효성 체크
     * @param caseId Case ID
     * @param webKey URL webKey
     * @return Boolean 이미 업로드 완료 여부
     */
    @AuraEnabled
    public static Boolean checkCaseSession(String caseId, String webKey) {
        try {
            if (String.isBlank(caseId) || String.isBlank(webKey)) {
                return false;
            }

            List<ContentDocumentLink> docLinkList = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :caseId
            ];

            if (docLinkList.isEmpty()) {
                return false;
            }

            Set<Id> contentDocumentIdSet = new Set<Id>();
            for (ContentDocumentLink docLink : docLinkList) {
                if (docLink.ContentDocumentId != null) {
                    contentDocumentIdSet.add(docLink.ContentDocumentId);
                }
            }

            if (contentDocumentIdSet.isEmpty()) {
                return false;
            }

            List<ContentVersion> existingFileList = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIdSet
                AND webKey__c = :webKey
                LIMIT 1
            ];

            return !existingFileList.isEmpty();
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            throw new AuraHandledException('[' + e.getLineNumber() + ']' + e.getMessage());
        }
    }

    /**
     * 파일 업로드
     * 261030 EXIF(위치정보) 제거를 위해 lightning-file-upload 대신 LWC 에서 이미지를 재인코딩(메타데이터 제거)한 뒤
     *        base64 로 전달받아 ContentVersion 을 생성하도록 재사용
     *        - webKey__c 를 생성 시점에 바로 저장 (updateContentVersionWebKey 별도 호출 불필요)
     *        - 생성된 ContentVersion Id 목록을 반환하여 syncOfflineVocFiles 호출에 사용
     * @param caseId Case ID
     * @param webKey URL webKey
     * @param fileMap Map<String, Object> 파일명 : base64 문자열
     * @return Map<String, Object> status, message, contentVersionIdList
     */
    @AuraEnabled
    public static Map<String, Object> uploadFile(String caseId, String webKey, Map<String, Object> fileMap){
        Map<String, Object> returnMap = new Map<String, Object>();
        try {
            // 입력값 검증
            if (String.isBlank(caseId) || String.isBlank(webKey) || fileMap == null || fileMap.isEmpty()) {
                returnMap.put('status', 'W');
                returnMap.put('message', '필수 정보가 누락되었습니다.');
                return returnMap;
            }

            if (fileMap.size() > MAX_UPLOAD_FILE_COUNT) {
                returnMap.put('status', 'W');
                returnMap.put('message', '최대 ' + MAX_UPLOAD_FILE_COUNT + '개의 파일만 업로드할 수 있습니다.');
                return returnMap;
            }

            // 이미 업로드 완료된 URL 인지 서버에서도 재확인 (중복 업로드 방지)
            if (checkCaseSession(caseId, webKey)) {
                returnMap.put('status', 'W');
                returnMap.put('message', '이미 파일 첨부가 완료된 URL입니다.');
                return returnMap;
            }

            List<ContentVersion> cvList = new List<ContentVersion>();
            for (String key : new List<String>(fileMap.keySet())) {
                ContentVersion cv = new ContentVersion();
                cv.Title = key;
                cv.PathOnClient = key;
                cv.VersionData = EncodingUtil.base64Decode((String)fileMap.get(key));
                cv.IsMajorVersion = true;
                cv.GuestRecordfileupload__c = caseId;
                cv.webKey__c = webKey;
                cvList.add(cv);
                // heap 절약: 디코딩한 base64 문자열 참조 해제
                fileMap.remove(key);
            }
            insert cvList;

            List<String> contentVersionIdList = new List<String>();
            for (ContentVersion cv : cvList) {
                contentVersionIdList.add(cv.Id);
            }

            returnMap.put('status', 'S');
            returnMap.put('message', '파일 업로드 성공');
            returnMap.put('contentVersionIdList', contentVersionIdList);
        } catch (Exception e) {
            System.debug('파일 업로드 실패: ' + '[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            returnMap.put('status', 'E');
            returnMap.put('message', '파일 업로드 실패: ' + e.getMessage());
        }
        return returnMap;
    }

    @AuraEnabled
    public static Map<String, Object> deleteFiles(List<String> contentVersionIdList){
        Map<String, Object> returnMap = new Map<String, Object>();
        try {
            if (contentVersionIdList == null || contentVersionIdList.isEmpty()) {
                returnMap.put('status', 'W');
                returnMap.put('message', '필수 정보가 누락되었습니다.');
                return returnMap;
            }

            Set<Id> contentDocumentIdSet = new Set<Id>();
            List<ContentVersion> cvList = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :contentVersionIdList];
            for (ContentVersion cv : cvList) {
                if (cv.ContentDocumentId != null) {
                    contentDocumentIdSet.add(cv.ContentDocumentId);
                }
            }

            List<ContentDocument> cdList = [SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIdSet];
            if (cdList.isEmpty()) {
                returnMap.put('status', 'W');
                returnMap.put('message', '파일을 찾을 수 없습니다.');
                return returnMap;
            }

            delete cdList;

            returnMap.put('status', 'S');
            returnMap.put('message', '파일 삭제 성공');
        } catch (Exception e) {
            // throw new AuraHandledException(e.getMessage());
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            returnMap.put('status', 'E');
            returnMap.put('message', '파일 삭제 실패: ' + e.getMessage());
        }
        return returnMap;
    }

    @AuraEnabled
    public static Map<String, Object> updateContentVersionWebKey(List<String> contentVersionIdList, String webKey){
        Map<String, Object> returnMap = new Map<String, Object>();
        try {
            if (contentVersionIdList == null || contentVersionIdList.isEmpty() || String.isBlank(webKey)) {
                // throw new AuraHandledException('필수 정보가 누락되었습니다.');
                returnMap.put('status', 'W');
                returnMap.put('message', '필수 정보가 누락되었습니다.');
                return returnMap;
            }

            List<ContentVersion> cvList = [SELECT Id FROM ContentVersion WHERE Id IN :contentVersionIdList];
            if (cvList.isEmpty()) {
                returnMap.put('status', 'W');
                returnMap.put('message', '파일을 찾을 수 없습니다.');
                return returnMap;
            }

            for (ContentVersion cv : cvList) {
                cv.webKey__c = webKey;
            }
            update cvList;

            returnMap.put('status', 'S');
            returnMap.put('message', '파일 업데이트 성공');
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            returnMap.put('status', 'E');
            returnMap.put('message', '파일 업데이트 실패: ' + e.getMessage());
        }
        return returnMap;
    }

    @AuraEnabled
    public static Map<String, Object> syncOfflineVocFiles(String caseId, List<String> contentVersionIdList){
        Map<String, Object> returnMap = new Map<String, Object>();
        try {

            List<Case> caseList = [SELECT Id, Origin, OwnerId, ARSSkill__c FROM Case WHERE Id = :caseId LIMIT 1];

            if (caseList.isEmpty() || String.isBlank(caseList[0].Origin)) {
                returnMap.put('status', 'W');
                returnMap.put('message', 'Case를 찾을 수 없거나 Origin이 없습니다.');
                return returnMap;
            }

            if (String.isBlank(caseId) || contentVersionIdList == null || contentVersionIdList.isEmpty()) {
                returnMap.put('status', 'W');
                returnMap.put('message', '필수 정보가 누락되었습니다.');
                return returnMap;
            }

            Set<String> allowSyncSkillSet = new Set<String>{'901491', '901492', '901391', '901493', '901392', '901497', '901715'};

            Boolean syncOfflineOriginOk = caseList[0].Origin == '현장등록-O2O/시스템 VOC' || caseList[0].Origin == '현장등록-상품VOC' || caseList[0].Origin == '현장등록-사고/안전 VOC' ||
            (caseList[0].Origin == '전화' && String.isNotBlank(caseList[0].ARSSkill__c) && allowSyncSkillSet.contains(caseList[0].ARSSkill__c));

            if(syncOfflineOriginOk){
                Id ownerId = caseList[0].OwnerId;
                List<User> userList = [SELECT OliveOneUserId__c FROM User WHERE Id = :ownerId LIMIT 1];
                String oliveOneUserId = userList.isEmpty() ? null : userList[0].OliveOneUserId__c;
                System.enqueueJob(new OfflineVocFileRequestQueueable(caseId, contentVersionIdList, oliveOneUserId));
            }


            returnMap.put('status', 'S');
            returnMap.put('message', '오프라인 VOC 파일 동기화 요청 성공');
        } catch (Exception e) {
            System.debug('[' + e.getLineNumber() + ']' + e.getMessage() + ' ' + e.getStackTraceString());
            returnMap.put('status', 'E');
            returnMap.put('message', '오프라인 VOC 파일 동기화 요청 실패: ' + e.getMessage());
        }
        return returnMap;
    }
}
