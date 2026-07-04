/// 광고 제거 인앱결제 경계 계약(F-10).
///
/// features(설정 화면)는 이 추상 타입만 의존한다. 실제 `in_app_purchase` SDK 는
/// [InAppPurchaseService] 구현에만 갇힌다.
///
/// ## 서버 없음 — 진실의 원천은 "로컬 캐시 + 스토어 영수증"
/// 백엔드가 없으므로(PRD 7절) 광고 제거 여부([adsRemoved])의 즉시 진실값은 로컬
/// 캐시(SharedPreferences)다. 구매/복원 시 스토어(플레이/앱스토어)가 돌려주는
/// 영수증 이벤트로 그 캐시를 갱신한다. 영수증 유효성 검증 자체는 스토어·SDK 에
/// 위임한다.
///
/// ## 비소모성 + 복원
/// 광고 제거는 **일회성 비소모성**(구독 아님) 상품이다. 재설치·기기 변경 시
/// [restore] 로 되살릴 수 있어야 한다(스토어 정책상 비소모성은 복원 필수).
///
/// ## 스토어 미설정에서도 크래시 금지
/// 아직 스토어에 상품이 없다. [storeStatus] 가 unavailable 이거나
/// [loadRemoveAdsProduct] 가 null 을 주면 설정 UI 는 **우아하게 비활성**된다
/// (에러 다이얼로그 남발 금지).
abstract class PurchaseService {
  /// 구매 스트림 구독 시작 + 로컬 캐시 로드. 1회 호출.
  Future<void> initialize();

  /// 광고 제거 구매 여부(로컬 캐시 즉시값). 광고 게이트가 동기로 읽는다.
  bool get adsRemoved;

  /// 광고 제거 상태 변경 스트림. **구독 즉시 현재값을 1회 방출**하고, 이후 구매/
  /// 복원으로 값이 바뀔 때마다 방출한다(설정 화면 버튼 상태 실시간 반영).
  Stream<bool> adsRemovedStream();

  /// 스토어 결제 가능 여부(로그인·기기 지원 등). unavailable 이면 구매 UI 비활성.
  Future<StoreStatus> storeStatus();

  /// 광고 제거 상품 정보 조회. 스토어 미등록/조회 실패 시 null → UI 비활성.
  Future<RemoveAdsProduct?> loadRemoveAdsProduct();

  /// 구매 플로우 시작. 반환값은 "플로우를 띄웠는지"(true)이며, 실제 권한 반영은
  /// [adsRemovedStream] 으로 비동기 도착한다. 시작 자체 실패 시 false.
  Future<bool> buyRemoveAds();

  /// 이전 구매 복원 시작. 결과는 [adsRemovedStream] 으로 도착한다.
  Future<void> restore();

  /// 스트림 구독 해제.
  void dispose();
}

/// 스토어 결제 가용성.
enum StoreStatus { available, unavailable }

/// 광고 제거 상품 표시 정보(스토어에서 조회한 현지화 값).
class RemoveAdsProduct {
  const RemoveAdsProduct({
    required this.id,
    required this.title,
    required this.price,
  });

  final String id;

  /// 현지화된 상품명(스토어 콘솔 설정값).
  final String title;

  /// 현지화된 가격 문자열(예: "₩3,300"). 직접 포맷하지 않고 스토어 값을 그대로 쓴다.
  final String price;
}
