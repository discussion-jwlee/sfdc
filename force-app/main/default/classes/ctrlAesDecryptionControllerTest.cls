/************************************************************************************
* File Name         : ctrlAesDecryptionControllerTest
* Description       : Test for ctrlAesDecryptionController
*************************************************************************************/
@isTest
public with sharing class ctrlAesDecryptionControllerTest {

    private static void setConfig() {
        ctrlAesCipher.configOverride = new AES_Config__mdt(
            Key__c = '0123456789abcdef0123456789abcdef',
            IV__c  = 'abcdef9876543210'
        );
    }

    @isTest
    static void testDecryptSuccess() {
        setConfig();
        String plainText = 'testClientSecret';
        String cipherText = ctrlAesCipher.encrypt(plainText);

        Test.startTest();
        String result = ctrlAesDecryptionController.decrypt(cipherText);
        Test.stopTest();

        System.assertEquals(plainText, result, 'decrypted value should match original');
    }

    @isTest
    static void testDecryptInvalidCipherText() {
        setConfig();
        AuraHandledException thrown;

        Test.startTest();
        try {
            ctrlAesDecryptionController.decrypt('invalidCipherText');
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, thrown, 'decrypt should throw AuraHandledException');
        System.assertEquals('복호화에 실패했습니다. 암호문이 올바른지 확인하세요.', thrown.getMessage());
    }
}
