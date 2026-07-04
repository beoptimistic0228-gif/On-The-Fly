import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/purchase_service.dart';
import '../../core/providers.dart';

/// 설정 화면의 광고 제거(F-10) 섹션 — 구매 버튼 + 복원 버튼.
///
/// ## 스토어 미설정에서도 우아하게 (핵심)
/// 아직 스토어에 상품이 없으므로 [PurchaseService.loadRemoveAdsProduct] 가 null,
/// [PurchaseService.storeStatus] 가 unavailable 을 줄 수 있다. 이때 크래시·에러
/// 다이얼로그 대신 **비활성 안내 타일**을 보여준다.
///
/// ## 광고 제거 상태는 반응형
/// 구매/복원 성공은 [adsRemovedProvider] 스트림으로 도착한다. 이 위젯은 그 값을
/// watch 하여 버튼을 즉시 "제거됨" 표시로 바꾼다(수동 새로고침 불필요).
class RemoveAdsSection extends ConsumerStatefulWidget {
  const RemoveAdsSection({super.key});

  @override
  ConsumerState<RemoveAdsSection> createState() => _RemoveAdsSectionState();
}

class _RemoveAdsSectionState extends ConsumerState<RemoveAdsSection> {
  bool _loading = true;
  bool _busy = false;
  RemoveAdsProduct? _product;
  StoreStatus _store = StoreStatus.unavailable;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    final svc = ref.read(purchaseServiceProvider);
    final store = await svc.storeStatus();
    final product = await svc.loadRemoveAdsProduct();
    if (!mounted) return;
    setState(() {
      _store = store;
      _product = product;
      _loading = false;
    });
  }

  Future<void> _buy() async {
    setState(() => _busy = true);
    final started = await ref.read(purchaseServiceProvider).buyRemoveAds();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!started) {
      _snack('지금은 구매를 시작할 수 없어요. 잠시 후 다시 시도해 주세요.');
    }
    // 성공 시 결과는 adsRemovedProvider 스트림으로 도착해 UI 가 갱신된다.
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    await ref.read(purchaseServiceProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('구매 복원을 요청했어요. 이전에 구매했다면 곧 광고가 제거돼요.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // 구매 여부(반응형). 로딩 전이면 스트림의 현재값(로컬 캐시)을 그대로 반영.
    final adsRemoved = ref.watch(adsRemovedProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('광고', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (adsRemoved)
          const ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text('광고가 제거되었어요'),
            subtitle: Text('완료 화면에 더 이상 광고가 표시되지 않아요.'),
          )
        else
          ..._buildPurchaseTiles(),
      ],
    );
  }

  List<Widget> _buildPurchaseTiles() {
    if (_loading) {
      return const [
        ListTile(
          leading: Icon(Icons.block_flipped),
          title: Text('광고 제거'),
          trailing: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ];
    }

    final available = _store == StoreStatus.available && _product != null;
    final product = _product;

    return [
      ListTile(
        enabled: available && !_busy,
        leading: const Icon(Icons.block_flipped),
        title: const Text('광고 제거'),
        subtitle: Text(
          available
              ? '한 번 구매로 완료 화면 광고를 영구히 없애요.'
              : '지금은 스토어에서 구매를 준비 중이에요.',
        ),
        trailing: _busy
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : FilledButton(
                onPressed: available ? _buy : null,
                child: Text(available ? (product?.price ?? '구매') : '준비 중'),
              ),
        onTap: available && !_busy ? _buy : null,
      ),
      ListTile(
        enabled: available && !_busy,
        leading: const Icon(Icons.restore),
        title: const Text('구매 복원'),
        subtitle: const Text('기기를 바꾸거나 앱을 다시 설치했다면 눌러 주세요.'),
        onTap: available && !_busy ? _restore : null,
      ),
    ];
  }
}
