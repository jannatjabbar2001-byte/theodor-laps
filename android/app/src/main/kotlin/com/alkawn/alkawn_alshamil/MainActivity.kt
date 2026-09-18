package com.alkawn.alkawn_alshamil

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "com.alkawn.storage"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				val preferences = getSharedPreferences("alkawn", Context.MODE_PRIVATE)
				when (call.method) {
					"loadVideos" -> result.success(preferences.getString("videos", "[]"))
					"saveVideos" -> {
						preferences.edit().putString("videos", call.arguments as String).apply()
						result.success(null)
					}
					else -> result.notImplemented()
				}
			}
	}
}
