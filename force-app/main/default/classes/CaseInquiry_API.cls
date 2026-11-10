/************************************************************************************
* File Name       : CaseInquiry_API
* Author          : DICUSSION
* Date            : 2026-11-10
* Tester          : CaseInquiry_API_Test.cls
* Description     : 고객ID(username__c) 기준 Case 조회 REST API
*                   - Case 스탠다드 필드 전체
*                   - Case에 연결된 파일(ContentDocument) 파일명/확장자/사이즈/생성일
*
* Endpoint : GET /services/apexrest/api/v1/cases?username={고객ID}
*
* Response (200)
* {
*   "success"   : true,
*   "message"   : null,
*   "totalSize" : 1,
*   "cases"     : [
*     {
*       "Id" : "500...", "CaseNumber" : "00001001", "Subject" : "...", ... (Case 스탠다드 필드 전체),
*       "files" : [
*         { "contentDocumentId" : "069...", "fileName" : "견적서", "fileExtension" : "pdf",
*           "fileSize" : 102400, "createdDate" : "2026-11-10T01:23:45.000Z" }
*       ]
*     }
*   ]
* }
*
* Error : 400(username 누락), 500(서버 오류) - { "success" : false, "message" : "..." }
*************************************************************************************/
@RestResource(urlMapping='/api/v1/cases/*')
global with sharing class CaseInquiry_API {

    // 한 번에 반환할 최대 Case 건수 (Heap/SOQL 한도 보호)
    @TestVisible private static final Integer MAX_CASES = 2000;

    @HttpGet
    global static void getCases() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json; charset=UTF-8');

        ResponseWrapper result = new ResponseWrapper();
        try {
            String username = req.params.get('username');
            if (String.isBlank(username)) {
                res.statusCode = 400;
                result.success = false;
                result.message = 'Required parameter is missing : username';
            } else {
                result.cases     = getCasesByUsername(username.trim());
                result.totalSize = result.cases.size();
                result.success   = true;
                res.statusCode   = 200;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, e.getMessage() + '\n' + e.getStackTraceString());
            res.statusCode = 500;
            result.success = false;
            result.message = e.getTypeName() + ' : ' + e.getMessage();
        }
        res.responseBody = Blob.valueOf(JSON.serialize(result));
    }

    /**
     * 고객ID(username__c) 기준으로 Case + 연결 파일 정보 조회
     */
    @TestVisible
    private static List<Map<String, Object>> getCasesByUsername(String username) {
        List<String> fieldNames = getStandardCaseFields();

        String soql = 'SELECT ' + String.join(fieldNames, ', ')
                    + ' FROM Case WHERE username__c = :username'
                    + ' ORDER BY CreatedDate DESC LIMIT ' + MAX_CASES;
        List<Case> caseList = Database.queryWithBinds(
            soql, new Map<String, Object>{ 'username' => username }, AccessLevel.USER_MODE);

        List<Map<String, Object>> resultList = new List<Map<String, Object>>();
        if (caseList.isEmpty()) return resultList;

        Map<Id, List<FileInfo>> filesByCaseId = getFilesByCaseIds(new Map<Id, Case>(caseList).keySet());

        for (Case c : caseList) {
            Map<String, Object> caseMap = new Map<String, Object>();
            for (String f : fieldNames) {
                caseMap.put(f, c.get(f));
            }
            List<FileInfo> files = filesByCaseId.get(c.Id);
            caseMap.put('files', files == null ? new List<FileInfo>() : files);
            resultList.add(caseMap);
        }
        return resultList;
    }

    /**
     * Case 오브젝트의 스탠다드 필드(커스텀 필드 제외) 중 조회 가능한 필드 목록
     */
    @TestVisible
    private static List<String> getStandardCaseFields() {
        List<String> fieldNames = new List<String>();
        for (Schema.SObjectField sf : Schema.SObjectType.Case.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = sf.getDescribe();
            if (dfr.isCustom() || !dfr.isAccessible()) continue;
            // Address/Location 같은 복합 필드는 구성 필드로 이미 조회되므로 제외
            Schema.DisplayType t = dfr.getType();
            if (t == Schema.DisplayType.ADDRESS || t == Schema.DisplayType.LOCATION) continue;
            fieldNames.add(dfr.getName());
        }
        fieldNames.sort();
        return fieldNames;
    }

    /**
     * Case에 연결된 파일(ContentDocumentLink -> ContentDocument) 조회
     */
    @TestVisible
    private static Map<Id, List<FileInfo>> getFilesByCaseIds(Set<Id> caseIds) {
        Map<Id, List<FileInfo>> filesByCaseId = new Map<Id, List<FileInfo>>();
        for (ContentDocumentLink cdl : [
                SELECT LinkedEntityId, ContentDocumentId,
                       ContentDocument.Title, ContentDocument.FileExtension,
                       ContentDocument.ContentSize, ContentDocument.CreatedDate
                  FROM ContentDocumentLink
                 WHERE LinkedEntityId IN :caseIds
                 ORDER BY ContentDocument.CreatedDate DESC]) {
            if (!filesByCaseId.containsKey(cdl.LinkedEntityId)) {
                filesByCaseId.put(cdl.LinkedEntityId, new List<FileInfo>());
            }
            filesByCaseId.get(cdl.LinkedEntityId).add(new FileInfo(cdl));
        }
        return filesByCaseId;
    }

    global class ResponseWrapper {
        public Boolean                   success;
        public String                    message;
        public Integer                   totalSize = 0;
        public List<Map<String, Object>> cases     = new List<Map<String, Object>>();
    }

    global class FileInfo {
        public String   contentDocumentId;
        public String   fileName;       // 파일명 (ContentDocument.Title)
        public String   fileExtension;  // 파일 확장자
        public Integer  fileSize;       // 파일 사이즈 (byte)
        public Datetime createdDate;    // 파일 생성일

        public FileInfo(ContentDocumentLink cdl) {
            this.contentDocumentId = cdl.ContentDocumentId;
            this.fileName          = cdl.ContentDocument.Title;
            this.fileExtension     = cdl.ContentDocument.FileExtension;
            this.fileSize          = cdl.ContentDocument.ContentSize;
            this.createdDate       = cdl.ContentDocument.CreatedDate;
        }
    }
}
