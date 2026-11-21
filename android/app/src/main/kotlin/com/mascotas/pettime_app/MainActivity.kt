package com.mascotas.pettime_app

import android.content.ContentValues
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

  // --- Placa NFC del collar (lib/services/nfc_tag_writer.dart) -------------------------------
  // Graba en un sticker NFC el link de la página de la chapita: quien encuentra a la mascota
  // apoya su celular y se le abre la página, sin tener PetTime.
  private var grabando: MethodChannel.Result? = null
  private var vuelta = 0
  private val principal = Handler(Looper.getMainLooper())

  override fun onPause() {
    terminarNfc("cancelado") // el modo para grabar solo anda con la app adelante
    super.onPause()
  }

  private fun estadoNfc(): String {
    val nfc = NfcAdapter.getDefaultAdapter(this) ?: return "sin"
    return if (nfc.isEnabled) "listo" else "apagado"
  }

  private fun grabarNfc(uri: String, result: MethodChannel.Result) {
    val nfc = NfcAdapter.getDefaultAdapter(this)
    if (nfc == null) {
      result.success("sin")
      return
    }
    if (!nfc.isEnabled) {
      result.success("apagado")
      return
    }
    terminarNfc("cancelado")
    grabando = result
    val estaVuelta = ++vuelta
    val mensaje = NdefMessage(arrayOf(NdefRecord.createUri(uri)))
    val tipos = NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
        NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V
    nfc.enableReaderMode(this, { tag -> escribirNfc(tag, mensaje) }, tipos, null)
    principal.postDelayed({ if (estaVuelta == vuelta) terminarNfc("tiempo") }, 60000)
  }

  // Corre en el hilo del lector NFC
  private fun escribirNfc(tag: Tag, mensaje: NdefMessage) {
    val respuesta = try {
      val ndef = Ndef.get(tag)
      if (ndef != null) {
        ndef.connect()
        try {
          when {
            !ndef.isWritable -> "bloqueado"
            ndef.maxSize < mensaje.toByteArray().size -> "chico"
            else -> {
              ndef.writeNdefMessage(mensaje)
              "ok"
            }
          }
        } finally {
          ndef.close()
        }
      } else {
        val nuevo = NdefFormatable.get(tag)
        if (nuevo != null) {
          nuevo.connect()
          try {
            nuevo.format(mensaje)
            "ok"
          } finally {
            nuevo.close()
          }
        } else {
          "noSirve"
        }
      }
    } catch (e: Exception) {
      "error"
    }
    principal.post { terminarNfc(respuesta) }
  }

  private fun terminarNfc(respuesta: String) {
    val resultado = grabando ?: return
    grabando = null
    vuelta++
    try {
      NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this)
    } catch (e: Exception) {
      // ya estaba apagado
    }
    resultado.success(respuesta)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pettime/nfc")
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "estado" -> result.success(estadoNfc())
            "grabar" -> grabarNfc(call.argument<String>("uri") ?: "", result)
            "cancelar" -> {
              terminarNfc("cancelado")
              result.success(null)
            }
            else -> result.notImplemented()
          }
        }
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
