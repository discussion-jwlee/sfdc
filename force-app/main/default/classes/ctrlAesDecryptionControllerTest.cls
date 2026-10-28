/************************************************************************************
* File Name         : ctrlAesDecryptionControllerTest
* Description       : Test for ctrlAesDecryptionController
*************************************************************************************/
@isTest
public with sharing class ctrlAesDecryptionControllerTest {

    @isTest
    static void testDecryptInvalidCipherText() {
        Boolean isThrown = false;

        Test.startTest();
        try {
            ctrlAesDecryptionController.decrypt('invalidCipherText');
        } catch (Exception e) {
            // ctrlAesCipher.AesException 은 AuraHandledException 으로 변환되어 throw 됨
            isThrown = true;
        }
        Test.stopTest();

        System.assert(isThrown, 'decrypt should throw an exception for invalid cipher text');
    }
}
