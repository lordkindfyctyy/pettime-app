package com.mascotas.pettime_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pettime/downloads")
        .setMethodCallHandler { call, result ->
          if (call.method != "save") {
            result.notImplemented()
            return@setMethodCallHandler
          }
          val name = call.argument<String>("name")
          val bytes = call.argument<ByteArray>("bytes")
          val mime = call.argument<String>("mime") ?: "application/octet-stream"
          if (name == null || bytes == null) {
            result.error("args", "Missing name or bytes", null)
            return@setMethodCallHandler
          }
          try {
            result.success(saveToDownloads(name, bytes, mime))
          } catch (e: Exception) {
            result.error("save", e.message, null)
          }
        }
  }

  /**
   * Writes [bytes] as a new file in the phone's Descargas folder, without a
   * "save as" screen: that screen sends PetTime to the background, and on
   * phones with little memory Android could close it before the file was
   * written (it ended up empty). Returns the name it was saved with, or null
   * below Android 10, where the app has no permission for it.
   */
  private fun saveToDownloads(name: String, bytes: ByteArray, mime: String): String? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
    val resolver = applicationContext.contentResolver
    val values = ContentValues().apply {
      put(MediaStore.Downloads.DISPLAY_NAME, name)
      put(MediaStore.Downloads.MIME_TYPE, mime)
      put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
      put(MediaStore.Downloads.IS_PENDING, 1)
    }
    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        ?: throw IllegalStateException("No se pudo crear el archivo")
    try {
      resolver.openOutputStream(uri)?.use { it.write(bytes) }
          ?: throw IllegalStateException("No se pudo escribir el archivo")
      values.clear()
      values.put(MediaStore.Downloads.IS_PENDING, 0)
      resolver.update(uri, values, null, null)
    } catch (e: Exception) {
      resolver.delete(uri, null, null)
      throw e
    }
    // Android may have added " (1)" if the name was taken.
    resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use {
      if (it.moveToFirst()) return it.getString(0)
    }
    return name
  }
}
