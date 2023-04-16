import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Environment
import android.speech.RecognitionAudio
import android.speech.RecognitionConfig
import android.speech.SpeechClient
import android.speech.SpeechRecognitionResult
import android.speech.SpeechRecognizer
import android.speech.SpeechSettings
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import okhttp3.*
import okio.ByteString
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.*


class MainActivity : AppCompatActivity(), TextToSpeech.OnInitListener {
    private val TAG = "MainActivity"
    private val MEDIA_TYPE_JSON = "application/json; charset=utf-8".toMediaType()
    private val API_URL = "https://api.openai.com/v1/engines/davinci-codex/completions"

    private lateinit var clipboardManager: ClipboardManager
    private lateinit var textToSpeech: TextToSpeech
    private lateinit var apiKey: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        // Initialize clipboard manager
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

        // Initialize text-to-speech engine
        textToSpeech = TextToSpeech(this, this)

        // Get API key from file or prompt user to enter it
        val apiKeyFile = File(getExternalFilesDir(null), "api_key.txt")
        if (apiKeyFile.exists()) {
            apiKey = apiKeyFile.readText()
        } else {
            apiKey = promptApiKey()
            apiKeyFile.writeText(apiKey)
        }

        // Start recording audio
        val audioData = recordAudio()

        // Convert speech to text using Google's Speech-to-Text API
        val text = convertSpeechToText(audioData)

        // Copy the converted text to clipboard
        runOnUiThread {
            copyTextToClipboard(text)
            sendToGpt(text)
        }
    }

    private fun promptApiKey(): String {
        var apiKey = ""
        runOnUiThread {
            val inputDialog = ApiKeyInputDialog(this)
            inputDialog.setOnOkClickListener { apiKey = inputDialog.getApiKey() }
            inputDialog.show()
        }
        while (apiKey.isEmpty()) {
            Thread.sleep(100)
        }
        return apiKey
    }

    private fun recordAudio(): ByteArray {
        val minBufferSize = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val audioRecorder = AudioRecord(MediaRecorder.AudioSource.MIC, 16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, minBufferSize)
        audioRecorder.startRecording()
        val recording = ByteArray(minBufferSize)
        var bytesRead: Int
        val buffer = ByteArray(4096)
        val outputStream = ByteArrayOutputStream()
        while (true) {
            bytesRead = audioRecorder.read(buffer, 0, buffer.size)
                        if (bytesRead == AudioRecord.ERROR_INVALID_OPERATION || bytesRead == AudioRecord.ERROR_BAD_VALUE) {
                Log.e(TAG, "Error reading audio data")
                break
            }
            if (bytesRead > 0) {
                outputStream.write(buffer, 0, bytesRead)
            }
            if (audioRecorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                break
            }
        }
        audioRecorder.stop()
        audioRecorder.release()
        return outputStream.toByteArray()
    }

    private fun convertSpeechToText(audioData: ByteArray): String {
        val client = SpeechClient.create()
        val audioBytes = RecognitionAudio.newBuilder().setContent(ByteString.copyFrom(audioData)).build()
        val config = RecognitionConfig.newBuilder().setEncoding(RecognitionConfig.AudioEncoding.LINEAR16).setSampleRateHertz(16000).setLanguageCode("en-US").build()
        val response = client.recognize(config, audioBytes)
        client.close()
        val result = response.resultsList[0]
        val alternative = result.alternativesList[0]
        return alternative.transcript
    }

    private fun copyTextToClipboard(text: String) {
        val clip = ClipData.newPlainText("text", text)
        clipboardManager.setPrimaryClip(clip)
    }

    private fun sendToGpt(text: String) {
        val requestBody = RequestBody.create(MEDIA_TYPE_JSON, createRequestJson(text))
        val request = Request.Builder()
            .url(API_URL)
            .header("Authorization", "Bearer $apiKey")
            .post(requestBody)
            .build()
        OkHttpClient().newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: java.io.IOException) {
                Log.e(TAG, "Failed to send request to GPT-3", e)
            }

            override fun onResponse(call: Call, response: Response) {
                val jsonString = response.body?.string()
                val jsonObject = JSONObject(jsonString)
                val completions = jsonObject.getJSONArray("completions")
                val completion = completions.getJSONObject(0)
                val text = completion.getString("text")
                runOnUiThread {
                    copyTextToClipboard(text)
                    speak(text)
                }
            }
        })
    }

    private fun createRequestJson(prompt: String): String {
        val jsonObject = JSONObject()
        jsonObject.put("prompt", prompt)
        jsonObject.put("max_tokens", 50)
        jsonObject.put("temperature", 0.5)
        return jsonObject.toString()
    }

    private fun speak(text: String) {
        textToSpeech.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
    }

    override fun onDestroy() {
        super.onDestroy()
        textToSpeech.stop()
        textToSpeech.shutdown()
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            textToSpeech.language = Locale.US
        } else {
            Log.e(TAG, "Failed to initialize text-to-speech engine")
        }
    }
}

