package com.example.mimic

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class KeystoreChannel : MethodChannel.MethodCallHandler {
    private val KEY_ALIAS = "mimic_vault_kek"
    private val ANDROID_KEYSTORE = "AndroidKeyStore"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensureKey" -> ensureKey(result)
            "wrap" -> wrapKey(call, result)
            "unwrap" -> unwrapKey(call, result)
            "deleteKey" -> deleteKey(result)
            "elapsedRealtime" -> result.success(android.os.SystemClock.elapsedRealtime())
            else -> result.notImplemented()
        }
    }

    private fun ensureKey(result: MethodChannel.Result) {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(KEY_ALIAS)) {
                result.success(true)
                return
            }

            try {
                generateKey(true)
            } catch (e: StrongBoxUnavailableException) {
                generateKey(false)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("KEYSTORE_ERROR", e.message, null)
        }
    }

    private fun generateKey(useStrongBox: Boolean) {
        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)

        if (useStrongBox) {
            builder.setIsStrongBoxBacked(true)
        }

        keyGenerator.init(builder.build())
        keyGenerator.generateKey()
    }

    private fun wrapKey(call: MethodCall, result: MethodChannel.Result) {
        try {
            val data = call.argument<ByteArray>("bytes") ?: return result.error("INVALID_ARG", "bytes required", null)
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            val secretKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
                ?: return result.error("KEY_INVALID", "Key missing", null)

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            
            val iv = cipher.iv
            val ciphertext = cipher.doFinal(data)
            
            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
            
            result.success(combined)
        } catch (e: Exception) {
            result.error("WRAP_ERROR", e.message, null)
        }
    }

    private fun unwrapKey(call: MethodCall, result: MethodChannel.Result) {
        try {
            val data = call.argument<ByteArray>("bytes") ?: return result.error("INVALID_ARG", "bytes required", null)
            if (data.size < 12) {
                return result.error("INVALID_DATA", "Data too short", null)
            }

            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            val secretKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            
            if (secretKey == null) {
                result.error("KEY_INVALID", "Key missing", null)
                return
            }

            val iv = data.copyOfRange(0, 12)
            val ciphertext = data.copyOfRange(12, data.size)

            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(128, iv))
            
            val plaintext = cipher.doFinal(ciphertext)
            result.success(plaintext)
        } catch (e: android.security.keystore.KeyPermanentlyInvalidatedException) {
            result.error("KEY_INVALID", "Key permanently invalidated", null)
        } catch (e: Exception) {
            result.error("KEY_INVALID", "Decryption failed or key missing", null)
        }
    }

    private fun deleteKey(result: MethodChannel.Result) {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            keyStore.deleteEntry(KEY_ALIAS)
            result.success(true)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", e.message, null)
        }
    }
}
