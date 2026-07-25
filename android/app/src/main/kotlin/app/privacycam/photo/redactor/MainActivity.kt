package app.privacycam.photo.redactor

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var videoBridge: PrivacyCamVideoBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoBridge = PrivacyCamVideoBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        videoBridge?.dispose()
        videoBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
