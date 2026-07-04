import 'purchase_service.dart';

/// [PurchaseService] 의 무동작(Noop) 구현.
///
/// 결제 기능이 없는 환경용:
/// 1. **테스트**: providers 기본값(플랫폼 채널 없이 안전).
/// 2. **폴백**: `main()` 이 IAP 초기화에 실패하면 주입해 앱을 지킨다.
///
/// 스토어가 항상 unavailable, 상품 없음, 구매/복원 무동작이므로 설정 UI 는 광고
/// 제거 버튼을 우아하게 비활성한 채 표시한다. 이미 구매한 사용자를 위해 [adsRemoved]
/// 초기값은 생성자로 주입 가능하게 둔다(폴백 시 로컬 캐시값 전달용).
class NoopPurchaseService implements PurchaseService {
  NoopPurchaseService([this._adsRemoved = false]);

  final bool _adsRemoved;

  @override
  Future<void> initialize() async {}

  @override
  bool get adsRemoved => _adsRemoved;

  @override
  Stream<bool> adsRemovedStream() async* {
    yield _adsRemoved;
  }

  @override
  Future<StoreStatus> storeStatus() async => StoreStatus.unavailable;

  @override
  Future<RemoveAdsProduct?> loadRemoveAdsProduct() async => null;

  @override
  Future<bool> buyRemoveAds() async => false;

  @override
  Future<void> restore() async {}

  @override
  void dispose() {}
}
