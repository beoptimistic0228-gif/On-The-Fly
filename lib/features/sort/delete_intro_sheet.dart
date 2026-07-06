import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// 삭제 최초 1회 교육 시트(D5, §0.2). 삭제 버튼을 처음 쓸 때만 바텀시트로 동작·
/// 안전망을 고지하고, 사용자가 이해한 뒤 [삭제]로 진행할 때만 실제 삭제가 이어진다.
/// 이후에는 무마찰(바로 삭제) — 플래그 `hasSeenDeleteIntro`(settings_store).
///
/// 반환: `true` = [삭제]로 진행, 그 외(취소·바깥 탭·시스템 back) = null/false.
Future<bool?> showDeleteIntroSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _DeleteIntroSheet(),
  );
}

class _DeleteIntroSheet extends StatelessWidget {
  const _DeleteIntroSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 플랫폼별 삭제 결과 고지(§0.2). iOS 는 "최근 삭제됨" 30일 복구, Android 는
    // 즉시 영구 삭제. 호스트/기타 플랫폼은 안전하게 영구 삭제 문구로 처리한다.
    final platformLine = Platform.isIOS
        ? "삭제한 사진은 '최근 삭제됨'으로 이동해요(30일 후 영구 삭제)."
        : '삭제하면 바로 영구 삭제돼요. 복구할 수 없어요.';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, 20 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline, color: scheme.error, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              '사진을 삭제할까요?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              platformLine,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              '원본은 폰 밖으로 나가지 않아요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            // 파괴적 액션이라 error 색 강조 버튼. 풀너비는 SizedBox 로 옵트인
            // (테마 minimumSize 무한 너비 금지 — theme.dart 주석 참조).
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('삭제'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
