# 프리미엄 요양원 입소 상담 — Salesforce Web-to-Lead 데모

## 구성

| 경로 | 내용 |
|---|---|
| `web-to-lead/index.html` | 상담 신청 폼 (Web-to-Lead) |
| `web-to-lead/thanks.html` | 제출 완료(retURL) 페이지 |
| `force-app/main/default/objects/Lead/fields/` | 리드 커스텀 필드 6종 |
| `force-app/main/default/standardValueSets/LeadSource.standardValueSet-meta.xml` | 유입 경로(리드 소스) 값 |
| `force-app/main/default/permissionsets/LifecareLeadFields.permissionset-meta.xml` | 커스텀 필드 FLS 권한 세트 |

## 필드 매핑

| 폼 항목 | 리드 필드 | 유형 | Web-to-Lead name |
|---|---|---|---|
| 관심시설 | `InterestedFacility__c` | 선택 목록 (쏠라체 홈 미사 / 쏠라체 홈 해운대 / 분당데이케어센터) | 00N… |
| 최초 문의일 | `FirstInquiryDate__c` | 날짜 (기본값: 오늘) | 00N… |
| 유입 경로 | `LeadSource` (표준) | 선택 목록 | `lead_source` |
| 어르신 성함 | `SeniorName__c` | 텍스트(80) | 00N… |
| 자녀(보호자) 성함 | `LastName` (표준) | 이름 | `last_name` |
| 어르신과의 관계 | `GuardianRelationship__c` | 선택 목록 (자녀 / 며느리 / 배우자) | 00N… |
| 이메일 | `Email` (표준) | 이메일 | `email` |
| 휴대폰 번호 | `MobilePhone` (표준) | 전화 | `mobile` |
| 마케팅 수신동의 | `MarketingOptIn__c` | 체크박스 (선택) | 00N… (체크 시 `1`) |
| 개인정보 수집동의 | `PrivacyConsent__c` | 체크박스 (필수) | 00N… (체크 시 `1`) |
| (자동) 회사 | `Company` (표준) | — | `company` = "{어르신 성함} 어르신 (개인)" |

> 리드의 이름(LastName)은 실제 연락 대상인 **보호자**로 저장하고, 어르신 성함은 별도 필드에 둡니다.
> 리드 변환 시 보호자가 연락처(Contact)가 됩니다.

## 설정 순서

1. **메타데이터 배포**
   ```bash
   sf project deploy start --source-dir force-app/main/default/objects/Lead force-app/main/default/standardValueSets force-app/main/default/permissionsets
   sf org assign permset --name LifecareLeadFields
   ```
   ⚠️ `LeadSource` StandardValueSet 배포 시 조직의 기존 리드 소스 값 목록이 이 파일의 값으로 대체됩니다. 데모 조직이 아니라면 해당 파일을 빼고 값을 수동으로 추가하세요.
2. **Web-to-Lead 활성화** — 설정 › 웹 투 리드 › 편집 › 사용, 기본 리드 작성자 지정, reCAPTCHA는 데모에서는 해제.
3. **ID 확인** — 설정 › 웹 투 리드 › *웹 투 리드 양식 생성*에서 위 커스텀 필드를 추가해 생성된 HTML의 `oid`와 `00N…` ID를 확인.
4. **`index.html`의 `CONFIG` 수정**
   - `oid`, `fieldIds`, 필요 시 `action`(My Domain 엔드포인트)
   - `dateFormat`: 기본 리드 작성자 로캘 형식 (`ko_KR` → `YYYY. M. D.`, `en_US` → `M/D/YYYY`). 형식이 틀리면 날짜가 비어 저장됩니다.
   - 처음 연결할 때는 `debug: true`로 두면 Salesforce가 수신한 값을 화면에 보여줍니다.
5. 페이지를 웹서버에 올리거나 로컬에서 실행:
   ```bash
   cd web-to-lead && python3 -m http.server 8080
   ```

## 데모 팁

- `?source=네이버 검색` 또는 `?utm_source=naver|blog|ad|agent` 파라미터로 유입 경로가 자동 선택됩니다. 채널별 링크를 따로 만들어 유입 경로 리포트를 시연할 수 있습니다.
- 휴대폰 번호는 입력 중 자동으로 하이픈이 들어가며, 필수 항목/형식 검증 후 전송됩니다.
- 관심시설 값을 바꿀 때는 `InterestedFacility__c` 선택 목록과 `index.html`의 라디오 버튼을 함께 수정하세요.
