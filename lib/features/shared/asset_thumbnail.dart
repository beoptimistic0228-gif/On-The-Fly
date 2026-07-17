import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 썸네일 요청 키(자산 id + 요청 크기). 캐싱 단위.
@immutable
class ThumbRequest {
  const ThumbRequest(this.assetId, {this.size = 200});

  final String assetId;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is ThumbRequest && other.assetId == assetId && other.size == size;

  @override
  int get hashCode => Object.hash(assetId, size);
}

/// 썸네일 지연 로드 + 캐싱(PhotoService.thumbnail 계약 사용).
/// Riverpod 이 결과를 캐싱하므로 스크롤·재빌드 시 재로드가 줄어든다.
final thumbnailProvider =
    FutureProvider.autoDispose.family<Uint8List?, ThumbRequest>((ref, req) {
  // 로드 완료된 썸네일은 잠깐 유지해 재진입 시 깜빡임을 줄인다.
  ref.keepAlive();
  return ref.watch(photoServiceProvider).thumbnail(req.assetId, size: req.size);
});

/// 자산 썸네일 위젯. 로딩/에러/영상 오버레이 처리.
class AssetThumbnail extends ConsumerWidget {
  const AssetThumbnail({
    super.key,
    required this.assetId,
    this.mediaType = 0,
    this.size = 200,
    this.fit = BoxFit.cover,
    this.showVideoBadge = true,
  });

  final String assetId;
  final int mediaType;
  final int size;
  final BoxFit fit;
  final bool showVideoBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(thumbnailProvider(ThumbRequest(assetId, size: size)));
    final scheme = Theme.of(context).colorScheme;

    return async.when(
      loading: () => Container(
        color: scheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, stack) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: scheme.outline),
      ),
      data: (bytes) {
        if (bytes == null) {
          return Container(
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.image_not_supported_outlined, color: scheme.outline),
          );
        }
        // 스크린리더에 "사진/영상 썸네일"임을 알린다(이미지엔 대체 텍스트가 없으면
        // 무의미한 노드가 된다). 재생 아이콘은 장식이라 시맨틱에서 제외한다.
        return Semantics(
          image: true,
          label: mediaType == 1 ? '영상 썸네일' : '사진 썸네일',
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(bytes, fit: fit, gaplessPlayback: true),
              if (showVideoBadge && mediaType == 1)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
