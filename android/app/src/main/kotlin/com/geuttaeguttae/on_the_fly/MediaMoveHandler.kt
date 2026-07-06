package com.geuttaeguttae.on_the_fly

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel

/**
 * 여러 앨범으로의 배치 이동을 "단일" 시스템 쓰기 동의(MediaStore.createWriteRequest)로 처리한다.
 *
 * 왜 필요한가(QA C-5): photo_manager 의 moveAssetsToPath 는 targetPath 1개당 동의창 1회라,
 * 앨범 N개에 배정하면 동의창이 N번 뜬다("대량 정리 시 UX 치명적"). 여기서는 전체 pending
 * 자산의 쓰기 권한을 한 번에 요청(createWriteRequest)한 뒤, 승인되면 앨범별 RELATIVE_PATH
 * 갱신을 추가 동의 없이 수행한다.
 *
 * C-4: photo_manager 의 moveAssetsToPath 는 bool 반환이라 "사용자 취소"와 "이동 실패"를
 * 구분할 수 없었다. 여기서는 RESULT_CANCELED 를 명시적으로 받아 Dart 에 cancelled=true 로
 * 돌려준다(취소 시 예약 큐 유지, failed 0).
 *
 * Android 11(API 30) 미만은 createWriteRequest 미지원 → unsupported=true 로 돌려
 * Dart 가 레거시 경로(per-album moveAssetsToPath)로 폴백하게 한다.
 *
 * 프라이버시: 자산 참조(MediaStore _id)만 다루며 원본 바이트를 읽거나 앱 밖으로 내보내지 않는다.
 */
class MediaMoveHandler(private val context: Context) {

    // 다른 플러그인(photo_manager=40071 등)과 충돌하지 않는 고유 requestCode.
    private val requestCode = 45317

    private val mainHandler = Handler(Looper.getMainLooper())

    private data class Move(val id: Long, val uri: Uri, val relativePath: String)

    private var pendingMoves: List<Move>? = null
    private var pendingResult: MethodChannel.Result? = null
    private var activity: Activity? = null

    fun bindActivity(activity: Activity?) {
        this.activity = activity
    }

    /** MethodChannel 'moveToAlbums' 진입점. moves: [{id, mediaType, relativePath}]. */
    fun moveToAlbums(argsMoves: List<Map<String, Any?>>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(reply(unsupported = true, cancelled = false))
            return
        }
        val act = activity
        if (act == null) {
            // 액티비티 없음 → 쓰기 동의창을 띄울 수 없음. Dart 가 레거시로 폴백.
            result.error("no_activity", "Activity unavailable for write request", null)
            return
        }
        if (pendingResult != null) {
            result.error("busy", "Another move request is in progress", null)
            return
        }

        val moves = argsMoves.mapNotNull { m ->
            val idStr = m["id"] as? String ?: return@mapNotNull null
            val id = idStr.toLongOrNull() ?: return@mapNotNull null
            val mediaType = (m["mediaType"] as? Int) ?: 0
            val rel = m["relativePath"] as? String ?: return@mapNotNull null
            Move(id, contentUriFor(id, mediaType), normalizeRelative(rel))
        }
        if (moves.isEmpty()) {
            result.success(reply(unsupported = false, cancelled = false))
            return
        }

        pendingMoves = moves
        pendingResult = result
        try {
            val pendingIntent =
                MediaStore.createWriteRequest(context.contentResolver, moves.map { it.uri })
            act.startIntentSenderForResult(
                pendingIntent.intentSender,
                requestCode,
                null,
                0,
                0,
                0,
            )
        } catch (e: Exception) {
            pendingMoves = null
            pendingResult = null
            result.error("write_request_failed", e.message, null)
        }
    }

    /** MainActivity.onActivityResult 에서 위임. 우리 요청을 처리했으면 true. */
    fun handleActivityResult(reqCode: Int, resultCode: Int): Boolean {
        if (reqCode != requestCode) return false
        val result = pendingResult
        val moves = pendingMoves
        pendingResult = null
        pendingMoves = null
        if (result == null || moves == null) return true

        if (resultCode != Activity.RESULT_OK) {
            // 사용자가 동의창을 취소함(RESULT_CANCELED) → 명시적 cancelled(C-4).
            result.success(reply(unsupported = false, cancelled = true))
            return true
        }

        // 승인됨 → 추가 동의 없이 앨범별 RELATIVE_PATH 갱신. ContentResolver 배치 갱신은
        // 대량이면 무거우니 백그라운드에서 수행하고, 결과는 메인 스레드로 회신한다.
        val cr = context.contentResolver
        Thread {
            val moved = ArrayList<String>()
            val failed = ArrayList<String>()
            for (mv in moves) {
                try {
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.RELATIVE_PATH, mv.relativePath)
                    }
                    val updated = cr.update(mv.uri, values, null, null)
                    if (updated > 0) moved.add(mv.id.toString()) else failed.add(mv.id.toString())
                } catch (e: Exception) {
                    // 개별 실패(권한/무결성) → 실패로 표기. Dart 가 큐에 유지한다.
                    failed.add(mv.id.toString())
                }
            }
            val map = HashMap<String, Any>()
            map["unsupported"] = false
            map["cancelled"] = false
            map["moved"] = moved
            map["failed"] = failed
            mainHandler.post { result.success(map) }
        }.start()
        return true
    }

    private fun reply(unsupported: Boolean, cancelled: Boolean): Map<String, Any> {
        val map = HashMap<String, Any>()
        map["unsupported"] = unsupported
        map["cancelled"] = cancelled
        map["moved"] = emptyList<String>()
        map["failed"] = emptyList<String>()
        return map
    }

    private fun contentUriFor(id: Long, mediaType: Int): Uri {
        // AssetRef.mediaType: 0=사진, 1=영상. photo_manager 의 URI 구성과 동일하게 맞춘다.
        val base = if (mediaType == 1) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        return ContentUris.withAppendedId(base, id)
    }

    private fun normalizeRelative(path: String): String {
        // MediaStore RELATIVE_PATH 관례상 끝에 '/'. 앞뒤 슬래시 정리 후 하나만 붙인다.
        val trimmed = path.trim('/')
        return "$trimmed/"
    }
}
