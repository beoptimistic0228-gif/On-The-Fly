import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../home/home_providers.dart';

/// 제한(limited) 접근 안내 카드(D2 확정: 전체 접근 유도).
///
/// 부분 접근 정리는 MVP 미지원 → 전체 접근을 요청한다.
/// PhotoService 계약에 '설정 앱 열기'/'제한 선택 재표시' 메서드가 없어
/// [PhotoService.ensurePermission] 재호출로 전체 접근을 유도한다(한계: 아래 note).
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
              onPressed: () async {
                await ref.read(photoServiceProvider).ensurePermission();
                ref.invalidate(homeDataProvider);
              },
              child: const Text('전체 접근 허용'),
            ),
          ),
        ],
      ),
    );
  }
}
