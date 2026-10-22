package com.pmay.frontend

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // High-importance channel so application-update pushes show as heads-up notifications.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel("pmay_updates", "Application updates", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Status updates about your PMAY application"
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pmay/files").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "saveToDownloads" -> result.success(
                        saveToDownloads(call.argument<String>("name")!!, call.argument<ByteArray>("bytes")!!)
                    )
                    "openFile" -> {
                        openFile(Uri.parse(call.argument<String>("uri")!!))
                        result.success(null)
                    }
                    "shareWhatsApp" -> result.success(
                        shareWhatsApp(
                            call.argument<String>("name")!!,
                            call.argument<ByteArray>("bytes")!!,
                            call.argument<String>("text") ?: ""
                        )
                    )
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("FILE_ERROR", e.message, null)
            }
        }
    }

    /** Saves a PDF into the public Downloads folder. Returns a uri string that can be opened later. */
    private fun saveToDownloads(name: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create file in Downloads")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            return uri.toString()
        }
        // Android 9 and below (needs WRITE_EXTERNAL_STORAGE, declared for sdk <= 28)
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        var file = File(dir, name)
        var n = 1
        while (file.exists()) {
            file = File(dir, name.removeSuffix(".pdf") + " (" + n++ + ").pdf")
        }
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("application/pdf"), null)
        return FileProvider.getUriForFile(this, "$packageName.fileprovider", file).toString()
    }

    private fun openFile(uri: Uri) {
        val i = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(i) // throws ActivityNotFoundException when no PDF viewer is installed
    }

    /** Sends the PDF to WhatsApp (or WhatsApp Business); falls back to the system chooser. */
    private fun shareWhatsApp(name: String, bytes: ByteArray, text: String): String {
        val dir = File(cacheDir, "shared_docs").apply { mkdirs() }
        val file = File(dir, name)
        file.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)

        fun intent(pkg: String?) = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (pkg != null) setPackage(pkg)
        }
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            try {
                startActivity(intent(pkg))
                return pkg
            } catch (_: ActivityNotFoundException) {
            }
        }
        startActivity(Intent.createChooser(intent(null), "Share document"))
        return "chooser"
    }
}