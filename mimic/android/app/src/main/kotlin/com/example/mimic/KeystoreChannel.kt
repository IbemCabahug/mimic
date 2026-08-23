package com.example.mimic

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class KeystoreChannel : MethodChannel.MethodCallHandler {
    private val KEY_ALIAS = "mimic_vault_kek"
    private val BIO_KEY_ALIAS = "mimic_vault_bio_kek"
    private val ANDROID_KEYSTORE = "AndroidKeyStore"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensureKey" -> ensureKey(result)
            "wrap" -> wrapKey(call, result)
            "unwrap" -> unwrapKey(call, result)
            "deleteKey" -> deleteKey(result)
            "pbkdf2" -> pbkdf2(call, result)
            "elapsedRealtime" -> result.success(android.os.SystemClock.elapsedRealtime())
            "ensureBioKey" -> ensureBioKey(result)
            "deleteBioKey" -> deleteBioKey(result)
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

    private fun ensureBioKey(result: MethodChannel.Result) {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(BIO_KEY_ALIAS)) {
                result.success(true)
                return
            }

            try {
                ensureBioKey(true)
            } catch (e: StrongBoxUnavailableException) {
                ensureBioKey(false)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("KEYSTORE_ERROR", e.message, null)
        }
    }

    private fun ensureBioKey(useStrongBox: Boolean) {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(BIO_KEY_ALIAS)) {
            return
        }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val builder = KeyGenParameterSpec.Builder(
            BIO_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setInvalidatedByBiometricEnrollment(true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        if (useStrongBox) {
            builder.setIsStrongBoxBacked(true)
        }

        keyGenerator.init(builder.build())
        keyGenerator.generateKey()
    }

    private fun wrapKey(call: MethodCall, result: MethodChannel.Result) {
        val data = call.argument<ByteArray>("bytes") ?: return result.error("INVALID_ARG", "bytes required", null)
        try {
            result.success(performWrap(data))
        } catch (e: Exception) {
            result.error("WRAP_ERROR", e.message, null)
        }
    }

    private fun performWrap(data: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val secretKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: throw Exception("Key missing")

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(data)
        
        val combined = ByteArray(iv.size + ciphertext.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
        
        return combined
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
            // Alias deletion is safe here: this is only called during a full vault wipe/reset
            // when no live wrapped data depends on this key anymore.
            keyStore.deleteEntry(KEY_ALIAS)
            result.success(true)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", e.message, null)
        }
    }

    private fun deleteBioKey(result: MethodChannel.Result) {
        try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            keyStore.deleteEntry(BIO_KEY_ALIAS)
            result.success(true)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", e.message, null)
        }
    }

    private fun pbkdf2(call: MethodCall, result: MethodChannel.Result) {
        val password = call.argument<ByteArray>("password")
        val salt = call.argument<ByteArray>("salt")
        val iterations = call.argument<Int>("iterations")
        val keyLength = call.argument<Int>("keyLength")

        if (password == null || salt == null || iterations == null || keyLength == null) {
            result.error("INVALID_ARG", "Missing required arguments for pbkdf2", null)
            return
        }
        if (iterations < 1 || keyLength < 1) {
            result.error("INVALID_ARG", "iterations and keyLength must be >= 1", null)
            return
        }

        executor.execute {
            try {
                val derived = performPbkdf2(password, salt, iterations, keyLength)
                mainHandler.post { result.success(derived) }
            } catch (e: Exception) {
                mainHandler.post { result.error("PBKDF2_ERROR", e.message, null) }
            }
        }
    }

    private fun performPbkdf2(password: ByteArray, salt: ByteArray, iterations: Int, keyLength: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        val keySpec = SecretKeySpec(password, "HmacSHA256")
        mac.init(keySpec)

        val hLen = 32
        val l = (keyLength + hLen - 1) / hLen
        val r = keyLength - (l - 1) * hLen
        val result = ByteArray(keyLength)

        val saltWithInt = ByteArray(salt.size + 4)
        System.arraycopy(salt, 0, saltWithInt, 0, salt.size)

        for (i in 1..l) {
            saltWithInt[salt.size] = (i ushr 24).toByte()
            saltWithInt[salt.size + 1] = (i ushr 16).toByte()
            saltWithInt[salt.size + 2] = (i ushr 8).toByte()
            saltWithInt[salt.size + 3] = i.toByte()

            var u = mac.doFinal(saltWithInt)
            val block = u.clone()

            for (j in 2..iterations) {
                u = mac.doFinal(u)
                for (k in block.indices) {
                    block[k] = (block[k].toInt() xor u[k].toInt()).toByte()
                }
            }

            val destPos = (i - 1) * hLen
            val copyLen = if (i == l) r else hLen
            System.arraycopy(block, 0, result, destPos, copyLen)
        }

        return result
    }
}
