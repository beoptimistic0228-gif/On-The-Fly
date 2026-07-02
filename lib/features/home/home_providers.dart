import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/photo_permission.dart';
import '../../core/providers.dart';

/// 홈 화면이 한눈에 보여줄 데이터 묶음.
@immutable
class HomeData {
  const HomeData({
    required this.permission,
    required this.unclassifiedCount,
    required this.streakDays,
  });

  final PhotoPermission permission;
  final int unclassifiedCount;
  final int streakDays;

  bool get isEmpty => unclassifiedCount == 0;
}

/// 접근 권한이 없어 홈을 정상 표시할 수 없는 상태(에러 상태로 전이).
class PhotoAccessException implements Exception {
  const PhotoAccessException(this.permission);
  final PhotoPermission permission;
}

/// 홈 데이터 로드: 권한 확인 → 미분류 큐 개수 + streak.
///
/// 홈 재진입/정리 완료 후 `ref.invalidate(homeDataProvider)` 로 갱신한다.
final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final photo = ref.watch(photoServiceProvider);
  final processed = ref.watch(processedRepositoryProvider);

  final permission = await photo.ensurePermission();
  if (permission == PhotoPermission.denied) {
    // 권한 거부 → 에러 상태로 안내 카드 노출.
    throw const PhotoAccessException(PhotoPermission.denied);
  }

  final queue = await photo.loadUnclassifiedQueue();
  final streak = await processed.streakDays();

  return HomeData(
    permission: permission,
    unclassifiedCount: queue.length,
    streakDays: streak,
  );
});
