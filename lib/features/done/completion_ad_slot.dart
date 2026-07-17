import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings_store.dart';
import '../../core/monetization/ad_gate.dart';
import '../../core/monetization/ad_service.dart';
import '../../core/providers.dart';

/// 완료 화면 광고 슬롯(F-09) — 축하·streak **통계 아래**에만 놓인다.
///
/// ## 이 위젯이 지키는 불변식
/// - **위치**: 완료 화면에서만, 그것도 통계 아래 슬롯에서만 그려진다. 정리(스와이프)
///   화면은 이 위젯을 절대 포함하지 않으므로 "정리 흐름 중 삽입" 이 원천 불가능하다.
/// - **게이트**: 노출 여부는 순수 정책 [AdGate.shouldShowCompletionAd] 만 따른다
///   (첫 정리+7일·광고 미제거·세션당 1회).
/// - **UX 인질 금지**: 게이트 불통과·SDK 미지원·로드 실패면 조용히 빈 위젯을 반환해
///   완료 화면이 광고 없이 정상 표시된다.
///
/// 세션당 1회는 로드 "성공" 시점에 [AdSession.completionAdShown] 을 세워 보장한다.
class CompletionAdSlot extends ConsumerStatefulWidget {
  const CompletionAdSlot({super.key});

  @override
  ConsumerState<CompletionAdSlot> createState() => _CompletionAdSlotState();
}

class _CompletionAdSlotState extends ConsumerState<CompletionAdSlot> {
  CompletionBanner? _banner;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    // 게이트 판정 — firstSortDate 는 DoneScreen 이 진입 시 이미 기록(캐시 동기 반영).
    final settings = ref.read(appSettingsProvider);
    final purchase = ref.read(purchaseServiceProvider);
    final session = ref.read(adSessionProvider);

    final allowed = AdGate.shouldShowCompletionAd(
      firstSortDate: settings.firstSortDate,
      now: DateTime.now(),
      adsRemoved: purchase.adsRemoved,
      shownThisSession: session.completionAdShown,
    );
    if (!allowed) return;

    final banner = ref.read(adServiceProvider).createCompletionBanner();
    if (banner == null) return; // 미지원 플랫폼/미초기화 → 광고 없음.

    _banner = banner;
    final ok = await banner.load();
    if (!ok || !mounted) {
      banner.dispose();
      _banner = null;
      return;
    }
    // 로드 성공 = 실제 노출 확정 → 세션 1회 소진 + 분석.
    session.completionAdShown = true;
    ref.read(analyticsServiceProvider).logAdShown();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (!_ready || banner == null || banner.widget == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '광고',
            // 광고 고지 라벨 — outline(테두리용, 대비 낮음) 대신 onSurfaceVariant 로
            // 본문 대비(4.5:1) 확보. 법적 고지라 가독성이 중요하다.
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: banner.height,
            child: banner.widget,
          ),
        ],
      ),
    );
  }
}
