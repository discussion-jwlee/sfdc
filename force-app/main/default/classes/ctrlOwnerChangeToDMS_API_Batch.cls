/************************************************************************************
* File Name       : ctrlOwnerChangeToDMS_API_Batch
* Author         : DICUSSION
* Date          : 2026-04-23
* Tester         : ctrlOwnerChangeToDMS_API_Test.cls
* Description     : Account Owner변경시 DMS로 전송
* Step1 : 세일즈포스 --> DMS
*************************************************************************************/
public without sharing class ctrlOwnerChangeToDMS_API_Batch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
   public Boolean isSandbox{get;set;}

   public Database.QueryLocator start(Database.BatchableContext bc) {
      System.debug('--------------= start OK');

      isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
      system.debug( isSandbox );
      List<String> mzsRecordTypes = system.label.mzsRecordTypeIds.split(',');
      return Database.getQueryLocator([SELECT Id, old_owner_id__c, IsOwnerChange__c, BRN__c, MasterAccountId__r.BpCode__c, Owner.Email
                                             FROM Account WHERE IsOwnerChange__c = true AND RecordTypeID IN :mzsRecordTypes]);
   }

   public void execute(Database.BatchableContext bc, List<sObject> ls) {
      System.debug('--------------= execute OK');
      try{
         DMS_API_Infor__mdt dmsApiInfor = DMS_API_Infor__mdt.getInstance('dev');
         if(!isSandbox) dmsApiInfor = DMS_API_Infor__mdt.getInstance('prd');

         HttpRequest httpReq = new HttpRequest();
         HttpResponse httpRes = new HttpResponse();
         Http h_get = new Http();
         List<ReqBody> reqBodyList = new List<ReqBody>();
         List<Account> reqAccountList = new List<Account>();
         Set<String> ownerIds = new Set<String>();
         String       guId      = IF_Util.generateGuid();
         IF_Log       log       = new IF_Log();
         IF_Log.InterfaceLog infLog;

         for(Account acc:(List<Account>)ls){
            ownerIds.add(acc.old_owner_id__c);
         }
         map<String,User> oldOwnerMap = new map<String,User>([SELECT ID, Email FROM User WHERE ID IN: ownerIds]);

         for(Account acc:(List<Account>)ls){
            if(acc.BRN__c != null){
               ReqBody rBody = new ReqBody();
               rBody.businessRegistrationNumber = acc.BRN__c;
               rBody.bpCode = acc.MasterAccountId__r.BpCode__c;
               if(!isSandbox) rBody.currentSalesManagerEmail = oldOwnerMap.get(acc.old_owner_id__c).Email;
               rBody.newSalesManagerEmail = acc.Owner.Email;
               reqBodyList.add( rBody );
               //DMS 응답의 results[index]와 매칭시키기 위해 요청 순서와 동일하게 Account를 담아둠
               reqAccountList.add( acc );
            }
         }
         if(isSandbox || Test.isRunningTest()){
            reqBodyList = new List<ReqBody>();
            reqAccountList = new List<Account>();

            ReqBody rBody1 = new ReqBody();
            rBody1.businessRegistrationNumber = '3798102335';
            rBody1.bpCode = '108901';
            rBody1.currentSalesManagerEmail = 'jeseok@mz.co.kr';
            rBody1.newSalesManagerEmail = 'sjjo@mz.co.kr';
            reqBodyList.add( rBody1 );
            reqAccountList.add( null );

            ReqBody rBody2 = new ReqBody();
            rBody2.businessRegistrationNumber = '4942700288';
            rBody2.bpCode = '101994';
            rBody2.currentSalesManagerEmail = 'sjjo@mz.co.kr';
            rBody2.newSalesManagerEmail = 'kcr@megazone.com';
            reqBodyList.add( rBody2 );
            reqAccountList.add( null );
         }

         String reqJsonBody = JSON.serialize(reqBodyList);
         httpReq.setHeader('DMS-Api-Token', dmsApiInfor.token__c);
         httpReq.setHeader('Content-Type', 'application/json');

         httpReq.setBody(reqJsonBody);
         httpReq.setEndpoint(dmsApiInfor.endpoint__c);
         httpReq.setMethod('PATCH');

         System.debug('JSON BODY');
         System.debug('////////////////////////////////////////////////////////////////////////////////');
         System.debug(JSON.serializePretty(reqBodyList));
         System.debug('////////////////////////////////////////////////////////////////////////////////');

         if(!Test.isRunningTest()) httpRes = h_get.send(httpReq);

         //DMS 응답의 results 중 status가 SUCCESS인 건에 해당하는 Account만 후속처리 업데이트
         List<Account> accountList = new List<Account>();
         if(httpRes.getStatusCode() == 200 && String.isNotBlank(httpRes.getBody())){
            Map<String, Object> resBodyMap = (Map<String, Object>) JSON.deserializeUntyped(httpRes.getBody());
            List<Object> results = (List<Object>) resBodyMap.get('results');
            if(results != null){
               for(Object resultObj : results){
                  Map<String, Object> result = (Map<String, Object>) resultObj;
                  String status = (String) result.get('status');
                  Integer idx = result.get('index') == null ? null : Integer.valueOf(String.valueOf(result.get('index')));

                  if('SUCCESS'.equalsIgnoreCase(status) && idx != null && idx >= 0 && idx < reqAccountList.size() && reqAccountList[idx] != null){
                     Account acc = reqAccountList[idx];
                     acc.IsOwnerChange__c = false;
                     acc.old_owner_id__c = '';
                     accountList.add(acc);
                  }
               }
            }
         }

         if(accountList.size() > 0) update accountList;

         infLog = new IF_Log.InterfaceLog( 'OwnerChangeToDMS_API ', guId, 'ctrlOwnerChangeToDMS_API_Batch', 'sendBuffer', reqJsonBody, httpRes.getBody(), String.valueOf(httpRes.getStatusCode()));
         log.createLog(infLog);
      }catch(Exception e){
         system.debug('//================= Exception ================//');
         system.debug('Error Line:'+e.getLineNumber());
         system.debug('Error Mag:'+e.getMessage());
         system.debug('Exception:'+e);
      }
   }

   public void finish(Database.BatchableContext bc) {
      System.debug('--------------= finish OK');
   }

   public class ReqBody {
      public String businessRegistrationNumber {get; set;}
      public String bpCode {get; set;}
      public String currentSalesManagerEmail {get; set;}
      public String newSalesManagerEmail {get; set;}
   }
}
