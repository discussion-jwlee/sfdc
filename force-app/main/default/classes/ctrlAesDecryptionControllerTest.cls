/************************************************************************************
* File Name         : ctrlAesDecryptionControllerTest
* Description       : Test for ctrlAesDecryptionController
*************************************************************************************/
@isTest
public with sharing class ctrlAesDecryptionControllerTest {

    @isTest
    static void testDecryptSuccess() {
        String plainText = 'testClientSecret';
        String cipherText = ctrlAesTestDataFactory.encrypt(plainText);
        System.assertNotEquals(null, cipherText, 'could not build cipher text from AES_Config__mdt');

        Test.startTest();
        String result = ctrlAesDecryptionController.decrypt(cipherText);
        Test.stopTest();

        System.assertEquals(plainText, result, 'decrypted value should match original');
    }

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
