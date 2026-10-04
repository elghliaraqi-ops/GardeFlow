package com.huim6.huim6_planning

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.huim6.huim6_planning/widget"
        private const val EXTRA_WIDGET_ACTION = "gardeflow_widget_action"
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingWidgetAction = intent?.getStringExtra(EXTRA_WIDGET_ACTION)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialWidgetAction" -> {
                        val value = pendingWidgetAction
                        pendingWidgetAction = null
                        result.success(value)
                    }
                    "updateWidgetData" -> {
                        @Suppress("UNCHECKED_CAST")
                        val values = call.arguments as? Map<String, Any?> ?: emptyMap()
                        val prefs = getSharedPreferences(GardeFlowWidgetProvider.PREFS_NAME, MODE_PRIVATE)
                        val editor = prefs.edit()
                        values.forEach { (key, value) -> editor.putString(key, value?.toString().orEmpty()) }
                        editor.apply()
                        GardeFlowWidgetProvider.updateAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_WIDGET_ACTION)
        if (!action.isNullOrBlank()) {
            pendingWidgetAction = action
            widgetChannel?.invokeMethod("widgetAction", action)
        }
    }
}
