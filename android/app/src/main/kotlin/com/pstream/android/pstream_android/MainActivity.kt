package com.pstream.android.pstream_android

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeckoRuntimeManager.get(applicationContext)
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "veil/gecko_embed",
                GeckoEmbedViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }
}
