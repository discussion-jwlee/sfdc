global class ctrlMarketingCloudContactDeleteBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
   global static String accessToken = '';
   global static AES_Config__mdt pConfig = AES_Config__mdt.getInstance('Core_MCE');

   global Database.QueryLocator start(Database.BatchableContext bc){
      return Database.getQueryLocator([SELECT Contact_ID__c, Email__c FROM Delete_Contact_List__c WHERE isProcessed__c = false ORDER BY CreatedDate desc]);
   }

   global void execute(Database.BatchableContext bc, List<Delete_Contact_List__c> ls){
      //config for Access Token Request
      MCE_Rotate_Secret_Code__c dci = MCE_Rotate_Secret_Code__c.getValues( 'Delete Contact Integration' );

      String grantType = 'client_credentials';
      String clientID = dci.Secret_Key__c;      //client ID 변경 필요
      String clientSecret = ctrlAesDecryptionController.decrypt( dci.Secret_Code__c );  // client Secret 변경 필요
      String reqBody = '{' +
            '"grant_type" : "' + grantType + '",' +
            '"client_id" : "' + clientID + '",' +
            '"client_secret" : "' + clientSecret +'"' +
            '}';

      //Access Token Request/Response
      String authURL = pConfig.authURL__c+'/v2/token';  // Endpoint (auth) 변경 필요
      HttpRequest tokenReq = new HttpRequest();
      HttpResponse tokenResp = new HttpResponse();
      Http h_getToken = new Http();

      tokenReq.setHeader('Content-Type', 'application/json');
      tokenReq.setBody(reqBody);
      tokenReq.setEndpoint(authURL);
      tokenReq.setMethod('POST');
      system.debug(tokenReq);
      if (Test.isRunningTest()) {
         //tokenResp.setBody('');
         tokenResp = h_getToken.send(tokenReq);
      } else {
         tokenResp = h_getToken.send(tokenReq);
      }

      //get Access Token
      Map<String, Object> mapBody = (Map<String, Object>)JSON.deserializeUntyped(tokenResp.getBody());
      accessToken = mapBody.get('access_token').ToString();
      system.debug('Access Token successfully granted : ' + accessToken);

      reqBody = '';
      //send MC Rest API
      //외부 API Call시 리밋(최대26번)
      for(Delete_Contact_List__c dc:ls){
         String endpoint = pConfig.endpoint__c+'/contacts/v1/contacts/actions/delete?type=keys';
         HttpRequest httpReq = new HttpRequest();
         HttpResponse httpResp = new HttpResponse();
         Http h_get = new Http();
         // Configure the get request
         String authType = 'Bearer ' + accessToken;
         system.debug('auth : ' + authType);
         reqBody='{' +
               '"values" : ["' + dc.Contact_ID__c + '"],' +
               '"DeleteOperationType" : "ContactAndAttributes"' +
               '}';
         system.debug('ID that will be sent to SFMC : ' + dc.Contact_ID__c);

         httpReq.setHeader('Authorization', authType);
         httpReq.setHeader('Content-Type', 'application/json');
         httpReq.setBody(reqBody);
         httpReq.setEndpoint(endpoint);
         httpReq.setMethod('POST');
         system.debug(authType + accessToken);
         system.debug(httpReq);
         if (Test.isRunningTest()) {
            httpResp.setBody('');
         } else {
            httpResp = h_get.send(httpReq);
         }
         system.debug('httpResp : ' + httpResp);
         String returnBody = httpResp.getBody();
         system.debug(returnBody);
         dc.isProcessed__c = true;
      }
      if(ls.size() > 0) update ls;
   }

   global void finish(Database.BatchableContext bc){
      System.debug('--------------= FINISH OK');
   }

}
