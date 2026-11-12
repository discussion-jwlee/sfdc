# 프리미엄 요양원 입소 상담 — Salesforce Web-to-Lead 데모

## 구성

| 경로 | 내용 |
|---|---|
| `web-to-lead/index.html` | 상담 신청 폼 (Web-to-Lead) |
| `web-to-lead/thanks.html` | 제출 완료(retURL) 페이지 |
| `force-app/main/default/permissionsets/LifecareLeadFields.permissionset-meta.xml` | 아래 커스텀 필드 읽기/편집 권한 세트 |
| `force-app/main/default/standardValueSets/LeadSource.standardValueSet-meta.xml` | 상담 경로(리드 소스) 값 |

## 필드 매핑

| 화면 항목 | 리드 필드 | 유형 | Web-to-Lead name | 비고 |
|---|---|---|---|---|
| 입소시설 | `Admission_Facility__c` | 다중 선택 목록 | `00Nak00005dAlE9` | 필수, 복수 선택 시 같은 name으로 여러 값 전송 |
| 상담 경로 | `LeadSource` | 선택 목록 | `lead_source` | 필수, `?utm_source=` 로 자동 선택 |
| 어르신명 | `Company` | 텍스트(255) | `company` | 필수 |
| 어르신 나이 | `Elder_Age__c` | 숫자(3,0) | `00Nak00005d5QDm` | 선택, 1~120 |
| 어르신 성별 | `Elder_Gender__c` | 선택 목록 | `00Nak00005dE89Z` | 선택, 값: 남성 / 여성 |
| 보호자명 | `Name`(LastName) | 이름 | `last_name` | 필수 |
| 어르신과의 관계 | `GuardianRelationship__c` | 선택 목록 | `00Nak00005fPuT3` | 필수, 값: 자녀 / 며느리 / 배우자 |
| 휴대폰 | `MobilePhone` | 전화 | `mobile` | 필수, 하이픈 자동 입력 |
| 이메일 | `Email` | 이메일 | `email` | 필수 |
| 상담내용 | `Consultation_Content__c` | 긴 텍스트 영역 | `00Nak00005dEGn3` | 선택, 최대 2,000자 |
| 개인정보 수집동의 | `PrivacyConsent__c` | 확인란 | `00Nak00005fPzR7` | 필수, `1` 전송 |
| 개인정보 수집동의 날짜 | `PrivacyConsentDate__c` | 날짜 | `00Nak00005fPlFN` | **숨김**, 제출일 |
| 마케팅 수신동의 | `MarketingOptIn__c` | 확인란 | `00Nak00005fPqpO` | 선택, 동의 시에만 `1` 전송 |
| 마케팅 수신동의 날짜 | `MarketingOptInDate__c` | 날짜 | `00Nak00005fQ0Jx` | **숨김**, 동의 시에만 제출일 |
| 리드 레코드 유형 | `RecordTypeId` | 레코드 유형 | `recordType` | **숨김**, `012ak00000EvPuTAAV` |
| 리드 상태 | `Status` | 선택 목록 | — | 전송하지 않음 (조직 기본값) |

## 설정 순서

1. **Web-to-Lead 활성화** — 설정 › 웹 투 리드 › 편집 › 사용, 기본 리드 작성자 지정. 데모에서는 reCAPTCHA 해제.
2. **`index.html`의 `CONFIG` 수정**
   - `oid`: 설정 › 회사 정보의 조직 ID (00D…)
   - `action`: My Domain 엔드포인트를 쓰는 조직이면 `https://<MyDomain>.my.salesforce.com/servlet/servlet.WebToLead?encoding=UTF-8`
   - `dateFormat`: 기본 리드 작성자 로캘의 날짜 형식 (`ko_KR` → `YYYY. M. D.`, `en_US` → `M/D/YYYY`). 형식이 다르면 동의 날짜가 비어 저장됩니다.
   - 처음 연결할 때는 `debug: true`로 두면 Salesforce가 받은 값을 화면에 보여줍니다.
3. **선택 목록 값 확인** — 폼에서 보내는 값과 조직의 API 값이 정확히 같아야 저장됩니다.
   - 입소시설: `쏠라체 홈 미사`, `쏠라체 홈 해운대`, `분당데이케어센터`
   - 어르신 성별: `남성`, `여성`
   - 어르신과의 관계: `자녀`, `며느리`, `배우자`
   - 상담 경로: 홈페이지, 네이버 검색, 블로그/카페, 온라인 광고, 보험 설계사 소개, 지인 소개, 언론 보도, 기타
   - 레코드 유형 `012ak00000EvPuTAAV`에도 위 값들이 사용 가능으로 지정돼 있어야 합니다.
4. (선택) 권한 세트 배포
   ```bash
   sf project deploy start --source-dir force-app/main/default/permissionsets
   ```
   ⚠️ `LeadSource` StandardValueSet을 배포하면 조직의 기존 리드 소스 값 목록이 이 파일 값으로 대체됩니다. 조직에서 값을 직접 관리한다면 배포하지 마세요.
5. 로컬 실행
   ```bash
   cd web-to-lead && python3 -m http.server 8080
   ```
