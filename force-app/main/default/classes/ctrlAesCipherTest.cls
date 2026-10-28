/************************************************************************************
* File Name         : ctrlAesCipherTest
* Description       : Test for ctrlAesCipher
*************************************************************************************/
@isTest
public with sharing class ctrlAesCipherTest {
    private static final String TEST_KEY = '0123456789abcdef0123456789abcdef';  // 32 bytes
    private static final String TEST_IV  = 'abcdef9876543210';                  // 16 bytes

    private static void setConfig(String key, String iv) {
        ctrlAesCipher.configOverride = new AES_Config__mdt(Key__c = key, IV__c = iv);
    }

    private static String getErrorMessage(Boolean isEncrypt, String value) {
        try {
            if (isEncrypt) ctrlAesCipher.encrypt(value);
            else ctrlAesCipher.decrypt(value);
        } catch (ctrlAesCipher.AesException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void testEncryptDecrypt() {
        setConfig(TEST_KEY, TEST_IV);
        String plainText = 'testClientSecret 한글';

        Test.startTest();
        String cipherText = ctrlAesCipher.encrypt(plainText);
        String result = ctrlAesCipher.decrypt(' ' + cipherText + ' ');
        Test.stopTest();

        System.assertNotEquals(plainText, cipherText, 'value should be encrypted');
        System.assertEquals(plainText, result, 'decrypted value should match original');
    }

    @isTest
    static void testBlankValue() {
        setConfig(TEST_KEY, TEST_IV);
        System.assertEquals('암호화할 값을 입력하세요.', getErrorMessage(true, ''));
        System.assertEquals('복호화할 값을 입력하세요.', getErrorMessage(false, null));
    }

    @isTest
    static void testInvalidCipherText() {
        setConfig(TEST_KEY, TEST_IV);
        String expected = '복호화에 실패했습니다. 암호문이 올바른지 확인하세요.';
        // 잘못된 Base64 / 블록 길이 오류
        System.assertEquals(expected, getErrorMessage(false, 'invalidCipherText'));

        // 다른 키로 암호화된 값
        String cipherText = ctrlAesCipher.encrypt('testClientSecret');
        setConfig('fedcba9876543210fedcba9876543210', TEST_IV);
        System.assertEquals(expected, getErrorMessage(false, cipherText));
    }

    @isTest
    static void testMissingConfig() {
        setConfig(null, TEST_IV);
        System.assertEquals('AES 설정이 없습니다. 관리자에게 문의하세요.', getErrorMessage(true, 'value'));
    }

    @isTest
    static void testInvalidConfigLength() {
        setConfig('shortKey', TEST_IV);
        System.assertEquals('AES 설정이 올바르지 않습니다. 관리자에게 문의하세요.', getErrorMessage(true, 'value'));

        setConfig(TEST_KEY, 'shortIv');
        System.assertEquals('AES 설정이 올바르지 않습니다. 관리자에게 문의하세요.', getErrorMessage(false, 'value'));
    }
}
