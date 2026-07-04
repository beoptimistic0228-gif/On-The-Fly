import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// 제한(limited) 접근 안내 카드(D2 확정: 전체 접근 유도).
///
/// 부분 접근 정리는 MVP 미지원 → 전체 접근을 요청한다.
///
/// QA C-2: iOS 에서 이미 limited 면 `ensurePermission` 재호출은 시스템
/// 다이얼로그를 다시 띄우지 않아 무반응이었다. 이제 [PhotoService.openSystemSettings]
/// 로 설정 앱을 열어 "모든 사진"을 직접 켜게 한다. 설정에서 돌아오면(resume)
/// 호스트 화면이 권한을 재확인한다 — home 은 HomeScreen 의 앱 재개 관찰자,
/// onboarding 은 "다시 시도" 버튼.
class LimitedAccessCard extends ConsumerWidget {
  const LimitedAccessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '일부 사진만 접근이 허용됐어요',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '전체 미분류 사진을 정리하려면 전체 접근이 필요해요. '
            '설정에서 "모든 사진" 접근을 허용해 주세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              // C-2: 설정 앱을 연다(즉시 반환). 권한 반영은 설정에서 돌아온 뒤
              // 호스트 화면의 재확인 흐름이 처리한다.
              onPressed: () =>
                  ref.read(photoServiceProvider).openSystemSettings(),
              child: const Text('설정에서 전체 접근 허용'),
            ),
          ),
        ],
      ),
    );
  }
}
