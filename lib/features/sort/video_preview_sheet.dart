import 'package:flutter/material.dart';

import '../shared/asset_thumbnail.dart';

/// 영상 간이 미리보기(F-08).
///
/// 풀 플레이어·편집은 범위 밖. 별도 video 플러그인이 deps 에 없어(계약 미포함)
/// 현재는 큰 썸네일 + 재생 아이콘의 간이 프리뷰로 처리한다.
/// (실제 인라인 재생이 필요하면 video_player 의존성 추가가 선행되어야 함 — 보고 참조)
void showVideoPreview(BuildContext context, String assetId) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: AssetThumbnail(assetId: assetId, mediaType: 1, size: 800),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('닫기'),
            ),
          ),
        ],
      ),
    ),
  );
}
