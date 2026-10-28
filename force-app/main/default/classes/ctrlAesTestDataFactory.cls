/************************************************************************************
* File Name         : ctrlAesTestDataFactory
* Description       : Build cipher text that ctrlAesDecryptionController can decrypt
*                     (test only). AES_Config__mdt 값들을 키/IV 후보로 암호화한 뒤
*                     실제 decrypt() 결과로 검증하여 맞는 암호문을 찾는다.
*************************************************************************************/
@isTest
public class ctrlAesTestDataFactory {

    // 복호화 가능한 암호문을 찾지 못하면 null 반환
    public static String encrypt(String plainText) {
        Set<String> values = new Set<String>();
        for (AES_Config__mdt cfg : AES_Config__mdt.getAll().values()) {
            for (Object v : cfg.getPopulatedFieldsAsMap().values()) {
                if (v instanceof String) values.add((String) v);
            }
        }

        List<Blob> keys = new List<Blob>();
        List<Blob> ivs = new List<Blob>{ null };    // null = Managed IV
        for (String s : values) {
            for (Blob b : toBlobs(s)) {
                Integer size = b.size();
                if (size == 16 || size == 24 || size == 32) keys.add(b);
                if (size == 16) ivs.add(b);
            }
        }

        Blob data = Blob.valueOf(plainText);
        for (Blob key : keys) {
            String algorithm = 'AES' + (key.size() * 8);
            for (Blob iv : ivs) {
                Blob cipher;
                try {
                    cipher = (iv == null)
                        ? Crypto.encryptWithManagedIV(algorithm, key, data)
                        : Crypto.encrypt(algorithm, key, iv, data);
                } catch (Exception e) {
                    continue;
                }
                for (String candidate : new List<String>{ EncodingUtil.base64Encode(cipher), EncodingUtil.convertToHex(cipher) }) {
                    if (isDecryptable(candidate, plainText)) return candidate;
                }
            }
        }
        return null;
    }

    private static List<Blob> toBlobs(String s) {
        List<Blob> result = new List<Blob>{ Blob.valueOf(s) };
        try { result.add(EncodingUtil.base64Decode(s)); } catch (Exception e) {}
        try { result.add(EncodingUtil.convertFromHex(s)); } catch (Exception e) {}
        return result;
    }

    private static Boolean isDecryptable(String cipherText, String plainText) {
        try {
            return plainText == ctrlAesDecryptionController.decrypt(cipherText);
        } catch (Exception e) {
            return false;
        }
    }
}
