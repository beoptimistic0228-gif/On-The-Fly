import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics/analytics_service.dart';
import 'analytics/local_analytics_service.dart';
import 'db/album_repository.dart';
import 'db/app_database.dart';
import 'db/processed_repository.dart';
import 'monetization/ad_gate.dart';
import 'monetization/ad_service.dart';
import 'monetization/noop_ad_service.dart';
import 'monetization/noop_purchase_service.dart';
import 'monetization/purchase_service.dart';
import 'notifications/local_notification_service.dart';
import 'notifications/notification_service.dart';
import 'photo/photo_manager_photo_service.dart';
import 'photo/photo_service.dart';

/// core 서비스 주입 지점 — features 는 여기 노출된 프로바이더만 읽는다.
///
/// 모두 추상 타입(또는 DB)을 노출하므로 테스트에서 override(fake 주입) 가능.

/// 앱 로컬 DB(Drift). 앱 수명 동안 단일 인스턴스.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 처리 기록 리포지토리(중복 방지·streak).
final processedRepositoryProvider = Provider<ProcessedRepository>((ref) {
  return DriftProcessedRepository(ref.watch(appDatabaseProvider).processedDao);
});

/// 앱 관리 앨범 리포지토리.
final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return DriftAlbumRepository(ref.watch(appDatabaseProvider).albumDao);
});

/// 사진 라이브러리 서비스(권한·미분류 큐·stage/commit·앨범).
final photoServiceProvider = Provider<PhotoService>((ref) {
  return PhotoManagerPhotoService(
    ref.watch(processedRepositoryProvider),
    ref.watch(albumRepositoryProvider),
  );
});

/// 로컬 알림 서비스(매일 정시 리마인더).
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return LocalNotificationService();
});

/// 분석 계측 서비스(F-12). 실제 백엔드는 `main()` 이 부팅 때 결정해 override 로
/// 주입한다: Firebase 초기화 성공 시 `FirebaseAnalyticsService`, 실패(설정 파일
/// 부재) 시 `LocalAnalyticsService`(폴백). 여기 기본값은 override 되지 않는 환경
/// (테스트 등)을 위한 로컬 구현이다. features 콜사이트는 추상 타입만 의존하므로
/// 어느 구현이 주입돼도 무변경.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return LocalAnalyticsService();
});

/// 광고 서비스(F-09). 기본값은 무동작 Noop(테스트·미지원 환경 안전). `main()` 이
/// 부팅 때 AdMob 초기화에 성공하면 `AdMobAdService` 로 override 주입한다(analytics
/// 와 동일한 패턴). 완료 화면은 추상 [AdService] 만 의존하므로 무변경.
final adServiceProvider = Provider<AdService>((ref) {
  return NoopAdService();
});

/// 광고 제거 IAP 서비스(F-10). 기본값 Noop, `main()` 이 `InAppPurchaseService` 로
/// override 주입. 설정 화면은 추상 [PurchaseService] 만 의존.
final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  return NoopPurchaseService();
});

/// 앱 세션 1회 동안의 광고 노출 상태(세션당 1회 불변식). autoDispose 아님 →
/// 여러 정리 세션을 거쳐도 유지된다.
final adSessionProvider = Provider<AdSession>((ref) => AdSession());

/// 광고 제거 여부 반응형 스트림(설정 화면 버튼 상태·완료 화면 게이트용).
/// 구독 즉시 현재값을 1회 방출한다.
final adsRemovedProvider = StreamProvider<bool>((ref) {
  return ref.watch(purchaseServiceProvider).adsRemovedStream();
});
