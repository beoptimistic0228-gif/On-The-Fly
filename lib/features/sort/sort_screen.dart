import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/album_ref.dart';
import '../../core/models/asset_ref.dart';
import '../home/home_providers.dart';
import '../shared/asset_thumbnail.dart';
import 'album_picker_sheet.dart';
import 'sort_controller.dart';
import 'swipeable_card.dart';
import 'video_preview_sheet.dart';

/// 정리(스와이프) 화면 — MVP의 심장. stage → commit 흐름.
class SortScreen extends ConsumerStatefulWidget {
  const SortScreen({super.key});

  @override
  ConsumerState<SortScreen> createState() => _SortScreenState();
}

class _SortScreenState extends ConsumerState<SortScreen> {
  bool _finishing = false;

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sortControllerProvider);

    // 큐 소진 시 자동 commit(정상 이탈 경로).
    ref.listen(sortControllerProvider, (prev, next) {
      if (next.isExhausted && !_finishing) {
        _finish();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('정리'),
        actions: [
          if (state.status == SortStatus.ready && state.current != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${state.index + 1} / ${state.total}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
        ],
      ),
      body: switch (state.status) {
        SortStatus.loading => const _Centered(child: CircularProgressIndicator()),
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
                Text('정리하는 중...'),
              ],
            ),
          ),
        SortStatus.ready =>
          state.current == null ? const _Centered(child: CircularProgressIndicator()) : _SortReady(
              state: state,
              onSwipe: (dir) => _onSwipe(dir, state),
              onTapAsset: () => _onTapAsset(state.current!),
              onAssignTap: () => _openAlbumPicker(state.current!),
              onSkip: () =>
                  ref.read(sortControllerProvider.notifier).skipCurrent(),
              onUndo: () => ref.read(sortControllerProvider.notifier).undo(),
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
    required this.onSwipe,
    required this.onTapAsset,
    required this.onAssignTap,
    required this.onSkip,
    required this.onUndo,
    required this.onQuickAlbum,
    required this.onCommit,
  });

  final SortState state;
  final void Function(SwipeDir) onSwipe;
  final VoidCallback onTapAsset;
  final VoidCallback onAssignTap;
  final VoidCallback onSkip;
  final VoidCallback onUndo;
  final void Function(AlbumRef) onQuickAlbum;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = state.current!;
    final recent = state.albums.take(3).toList();

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SwipeableCard(
              key: ValueKey(asset.id),
              onSwipe: onSwipe,
              onTap: onTapAsset,
              child: Card(
                clipBehavior: Clip.antiAlias,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
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
        // 최근 앨범 퀵버튼.
        if (recent.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final a in recent)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      label: Text(a.name),
                      onPressed: () => onQuickAlbum(a),
                    ),
                  ),
              ],
            ),
          ),
        // 액션 버튼 행.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundAction(
                icon: Icons.schedule,
                label: '나중에',
                color: theme.colorScheme.outline,
                onTap: onSkip,
              ),
              _RoundAction(
                icon: Icons.undo,
                label: '되돌리기',
                color: theme.colorScheme.secondary,
                onTap: state.canUndo ? onUndo : null,
              ),
              _RoundAction(
                icon: Icons.folder_open,
                label: '앨범 배정',
                color: theme.colorScheme.primary,
                onTap: onAssignTap,
              ),
            ],
          ),
        ),
        // 스테이징 배너 + commit.
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.pendingCount > 0
                      ? '옮길 ${state.pendingCount}장 대기 중'
                      : '스와이프로 앨범에 배정해요',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: state.pendingCount > 0 ? onCommit : null,
                icon: const Icon(Icons.check),
                label: Text('정리 (${state.pendingCount})'),
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
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effective = enabled ? color : Theme.of(context).disabledColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: effective.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, color: effective, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: effective, fontSize: 12)),
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

class _DeniedView extends StatelessWidget {
  const _DeniedView({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 64),
          const SizedBox(height: 16),
          const Text('사진 접근이 필요해요', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('설정에서 사진 접근을 허용한 뒤 다시 시도해 주세요.',
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onBack, child: const Text('홈으로')),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64),
          const SizedBox(height: 16),
          const Text('사진을 불러오지 못했어요', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ),
        ],
      ),
    );
  }
}
