package com.geuttaeguttae.on_the_fly

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 배치 사진 이동(단일 쓰기 동의)을 위한 플랫폼 채널을 배선한다(QA C-5/C-4).
 *
 * 채널 `on_the_fly/media_store` 의 `moveToAlbums` 를 [MediaMoveHandler] 로 위임한다.
 * 그 외 사진 접근/썸네일/이동 폴백은 photo_manager 플러그인이 담당한다.
 */
class MainActivity : FlutterActivity() {
    private var mediaMoveHandler: MediaMoveHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = MediaMoveHandler(applicationContext).apply { bindActivity(this@MainActivity) }
        mediaMoveHandler = handler

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "on_the_fly/media_store")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToAlbums" -> {
                        val moves = call.argument<List<Map<String, Any?>>>("moves") ?: emptyList()
                        handler.moveToAlbums(moves, result)
                    }
                    // D5: 삭제 지원 판정용(Android API 30+ 만 노출). 초경량 즉답.
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 우리 쓰기-동의 요청이면 여기서 소비하고, 그 외(photo_manager 등)는 super 가 위임.
        mediaMoveHandler?.handleActivityResult(requestCode, resultCode)
        super.onActivityResult(requestCode, resultCode, data)
    }
}
