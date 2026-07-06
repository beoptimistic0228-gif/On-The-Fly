import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/settings_store.dart';
import '../../app/theme.dart';
import '../../core/models/album_ref.dart';
import '../../core/models/asset_ref.dart';
import '../../core/providers.dart';
import '../home/home_providers.dart';
import '../shared/asset_thumbnail.dart';
import 'album_picker_sheet.dart';
import 'delete_intro_sheet.dart';
import 'sort_controller.dart';
import 'swipeable_card.dart';
import 'video_preview_sheet.dart';

/// 정리(스와이프) 화면 — MVP의 심장. stage → commit 흐름.
///
/// 디자인: 사진이 주인공(원칙 1)이 되도록 화면 배경을 깊은 웜 차콜 "라이트박스"로
/// 두고, 조작 크롬(퀵 앨범 칩·액션·commit)은 하단 서피스 패널에 모아 최소화한다.
class SortScreen extends ConsumerStatefulWidget {
  const SortScreen({super.key});

  @override
  ConsumerState<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends ConsumerState<SortScreen> {
  bool _finishing = false;
  bool _deleting = false;

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final outcome = await ref.read(sortControllerProvider.notifier).commit();
    if (!mounted) {
      _finishing = false;
      return;
    }

    if (outcome.cancelled) {
      _finishing = false;
      _snack('정리를 완료하려면 동의가 필요해요. 예약은 그대로 남아 있어요.');
      return;
    }
    if (outcome.isNoop) {
      _finishing = false;
      // 배정한 사진이 없는데 큐가 소진됨 → 홈으로.
      if (ref.read(sortControllerProvider).isExhausted) {
        _snack('배정한 사진이 없어요. 다음에 또 정리해요!');
        ref.invalidate(homeDataProvider);
        context.go('/home');
      } else {
        _snack('먼저 사진을 앨범에 배정해 주세요.');
      }
      return;
    }
    // 성공(부분 포함) → 완료 화면으로 결과 전달.
    context.go('/done', extra: outcome);
    _finishing = false;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAlbumPicker(AssetRef asset) async {
    final album = await showAlbumPicker(context);
    if (album == null || !mounted) return;
    // 모달 여는 사이 카드가 넘어갔을 수 있으니 현재 자산이 동일할 때만 배정.
    final current = ref.read(sortControllerProvider).current;
    if (current?.id == asset.id) {
      ref.read(sortControllerProvider.notifier).assignCurrent(album);
    }
  }

  void _assignToRecent(AlbumRef album) {
    ref.read(sortControllerProvider.notifier).assignCurrent(album);
  }

  /// 저강도 삭제 버튼 탭 → (최초 1회) 교육 시트 → 즉시 삭제(D5, F-14c').
  Future<void> _onDelete() async {
    if (_deleting) return;
    _deleting = true;
    try {
      final asset = ref.read(sortControllerProvider).current;
      if (asset == null) return;

      // 최초 1회만 교육 시트. [삭제]로 진행할 때만 실제 삭제로 이어지고,
      // 그때 플래그를 세워 이후엔 무마찰로 바로 삭제한다(§0.2).
      final settings = ref.read(appSettingsProvider);
      if (!settings.hasSeenDeleteIntro) {
        final proceed = await showDeleteIntroSheet(context);
        if (proceed != true || !mounted) return;
        await settings.setSeenDeleteIntro();
      }

      // 시트를 여는 사이 카드가 넘어갔을 수 있으니 현재 자산이 동일할 때만 삭제.
      if (ref.read(sortControllerProvider).current?.id != asset.id) return;

      final ok = await ref.read(sortControllerProvider.notifier).deleteCurrent();
      if (!mounted) return;
      // 취소·실패 통합 문구(D5-6). 성공 시 카드가 이미 다음으로 넘어가 조용히 진행.
      if (!ok) _snack('삭제하지 못했어요');
    } finally {
      _deleting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sortControllerProvider);

    // 큐 소진 시 자동 commit(정상 이탈 경로).
    ref.listen(sortControllerProvider, (prev, next) {
      if (next.isExhausted && !_finishing) {
        _finish();
      }
    });

    final ready = state.status == SortStatus.ready && state.current != null;
    final progress = (ready && state.total > 0)
        ? (state.index + 1) / state.total
        : null;

    return Scaffold(
      backgroundColor: kSortCanvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        // 다크 라이트박스 위라 제목도 밝게(테마 titleTextStyle 이 onSurface=어두움
        // 이므로 여기서 흰색으로 덮는다).
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        title: const Text('정리'),
        actions: [
          if (ready)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Text(
                  '${state.index + 1} / ${state.total}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
        bottom: progress == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFFFFB68A)),
                ),
              ),
      ),
      body: switch (state.status) {
        SortStatus.loading =>
          const _Centered(child: CircularProgressIndicator()),
        SortStatus.denied => _DeniedView(onBack: () => context.go('/home')),
        SortStatus.error => _ErrorView(
            onRetry: () => ref.read(sortControllerProvider.notifier).load(),
          ),
        SortStatus.committing => const _Centered(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('정리하는 중...',
                    style: TextStyle(color: Colors.white70, fontSize: 15)),
              ],
            ),
          ),
        SortStatus.ready => state.current == null
            ? const _Centered(child: CircularProgressIndicator())
            : _SortReady(
                state: state,
                // supportsDeletion 은 동기 getter(서비스가 SDK 버전 캐시). false 면
                // 삭제 버튼을 아예 렌더하지 않는다(§G.2 1차 방어).
                showDelete: ref.read(photoServiceProvider).supportsDeletion,
                onSwipe: (dir) => _onSwipe(dir, state),
                onTapAsset: () => _onTapAsset(state.current!),
                onAssignTap: () => _openAlbumPicker(state.current!),
                onSkip: () =>
                    ref.read(sortControllerProvider.notifier).skipCurrent(),
                onUndo: () => ref.read(sortControllerProvider.notifier).undo(),
                onDelete: _onDelete,
                onQuickAlbum: _assignToRecent,
                onCommit: _finish,
              ),
      },
    );
  }

  void _onSwipe(SwipeDir dir, SortState state) {
    final asset = state.current;
    if (asset == null) return;
    switch (dir) {
      case SwipeDir.right:
        _openAlbumPicker(asset);
      case SwipeDir.left:
        ref.read(sortControllerProvider.notifier).skipCurrent();
      case SwipeDir.up:
        if (state.albums.isNotEmpty) {
          _assignToRecent(state.albums.first);
        } else {
          _openAlbumPicker(asset);
        }
    }
  }

  void _onTapAsset(AssetRef asset) {
    if (asset.mediaType == 1) {
      showVideoPreview(context, asset.id);
    }
  }
}

class _SortReady extends StatelessWidget {
  const _SortReady({
    required this.state,
    required this.showDelete,
    required this.onSwipe,
    required this.onTapAsset,
    required this.onAssignTap,
    required this.onSkip,
    required this.onUndo,
    required this.onDelete,
    required this.onQuickAlbum,
    required this.onCommit,
  });

  final SortState state;
  final bool showDelete;
  final void Function(SwipeDir) onSwipe;
  final VoidCallback onTapAsset;
  final VoidCallback onAssignTap;
  final VoidCallback onSkip;
  final VoidCallback onUndo;
  final VoidCallback onDelete;
  final void Function(AlbumRef) onQuickAlbum;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = state.current!;
    final recent = state.albums.take(3).toList();

    return Column(
      children: [
        // 사진 = 주인공. 라이트박스 위에 크게, 부드러운 그림자.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SwipeableCard(
              key: ValueKey(asset.id),
              onSwipe: onSwipe,
              onTap: onTapAsset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AssetThumbnail(
                    assetId: asset.id,
                    mediaType: asset.mediaType,
                    size: 800,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 하단 조작 패널 — 크롬을 여기 모아 사진 영역을 넓게 유지.
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 12 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 최근 앨범 퀵버튼 — 탭 1회 배정(원칙 2).
              if (recent.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final a in recent)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.folder_rounded, size: 18),
                            label: Text(a.name),
                            onPressed: () => onQuickAlbum(a),
                          ),
                        ),
                    ],
                  ),
                ),
              if (recent.isNotEmpty) const SizedBox(height: 12),
              // 액션 버튼 행. 좌단에 저강도 삭제(supportsDeletion 일 때만) → 나중에
              // → 되돌리기 → 배정(우단·강조). 삭제는 배정과 대각으로 떨어뜨려
              // 오조작을 막고, 시각 위계를 낮춰(subdued·error색) 배정을 주인공으로 둔다.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (showDelete)
                    _RoundAction(
                      icon: Icons.delete_outline,
                      label: '삭제',
                      color: theme.colorScheme.error,
                      subdued: true,
                      onTap: onDelete,
                    ),
                  _RoundAction(
                    icon: Icons.schedule,
                    label: '나중에',
                    color: theme.colorScheme.onSurfaceVariant,
                    onTap: onSkip,
                  ),
                  _RoundAction(
                    icon: Icons.undo_rounded,
                    label: '되돌리기',
                    color: theme.colorScheme.secondary,
                    onTap: state.canUndo ? onUndo : null,
                  ),
                  _RoundAction(
                    icon: Icons.folder_open_rounded,
                    label: '앨범 배정',
                    color: theme.colorScheme.primary,
                    prominent: true,
                    onTap: onAssignTap,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 스테이징 배너 + commit.
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.pendingCount > 0 ? '옮길 준비 완료' : '대기 중인 사진 없음',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.pendingCount > 0
                              ? '${state.pendingCount}장'
                              : '스와이프로 배정해요',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: state.pendingCount > 0 ? onCommit : null,
                    icon: const Icon(Icons.check_rounded),
                    label: Text('정리 (${state.pendingCount})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.prominent = false,
    this.subdued = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool prominent;

  /// 파괴적·비주류 액션(삭제)을 나머지보다 작게·저채도로 눌러 위계를 낮춘다(§2.1).
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effective = enabled ? color : Theme.of(context).disabledColor;
    // 배정 버튼은 판단→행동의 종착점이라 시각적으로 강조(채운 원)한다(원칙 2).
    // 삭제(subdued)는 반대로 고스트 배경을 더 옅게 해 유혹을 억제한다.
    final bg = prominent && enabled
        ? color
        : effective.withValues(alpha: subdued ? 0.10 : 0.14);
    final fg = prominent && enabled
        ? Theme.of(context).colorScheme.onPrimary
        : effective;
    final pad = prominent
        ? 18.0
        : subdued
            ? 12.0
            : 15.0;
    final iconSize = prominent
        ? 30.0
        : subdued
            ? 22.0
            : 26.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Icon(icon, color: fg, size: iconSize),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: effective,
                fontSize: subdued ? 11 : 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}

/// 정리 화면의 비정상 상태(권한/에러)는 다크 라이트박스 위에 표시되므로
/// 밝은 전경색으로 그린다.
class _DeniedView extends StatelessWidget {
  const _DeniedView({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _DarkStateView(
      icon: Icons.lock_outline,
      title: '사진 접근이 필요해요',
      message: '설정에서 사진 접근을 허용한 뒤 다시 시도해 주세요.',
      buttonLabel: '홈으로',
      onPressed: onBack,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _DarkStateView(
      icon: Icons.error_outline,
      title: '사진을 불러오지 못했어요',
      message: '잠시 후 다시 시도해 주세요.',
      buttonLabel: '다시 시도',
      onPressed: onRetry,
    );
  }
}

class _DarkStateView extends StatelessWidget {
  const _DarkStateView({
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: kSortCanvasElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ),
        ],
      ),
    );
  }
}
