import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/album_ref.dart';
import '../../core/models/asset_ref.dart';
import '../../core/models/photo_permission.dart';
import '../../core/providers.dart';

enum SortStatus { loading, ready, denied, committing, error }

/// 한 번의 스와이프 액션(Undo 스택용).
@immutable
class _SwipeAction {
  const _SwipeAction({
    required this.index,
    required this.assetId,
    required this.wasAssign,
  });

  final int index;
  final String assetId;
  final bool wasAssign;
}

/// 정리 화면 상태.
@immutable
class SortState {
  const SortState({
    this.status = SortStatus.loading,
    this.queue = const [],
    this.albums = const [],
    this.index = 0,
    this.pendingCount = 0,
    this.canUndo = false,
  });

  final SortStatus status;
  final List<AssetRef> queue;
  final List<AlbumRef> albums;
  final int index;
  final int pendingCount;
  final bool canUndo;

  /// 현재 카드 자산(큐 소진 시 null).
  AssetRef? get current => index >= 0 && index < queue.length ? queue[index] : null;

  bool get isExhausted => status == SortStatus.ready && current == null;

  int get total => queue.length;

  SortState copyWith({
    SortStatus? status,
    List<AssetRef>? queue,
    List<AlbumRef>? albums,
    int? index,
    int? pendingCount,
    bool? canUndo,
  }) {
    return SortState(
      status: status ?? this.status,
      queue: queue ?? this.queue,
      albums: albums ?? this.albums,
      index: index ?? this.index,
      pendingCount: pendingCount ?? this.pendingCount,
      canUndo: canUndo ?? this.canUndo,
    );
  }
}

/// commit 결과를 화면 전이용으로 요약.
@immutable
class CommitOutcome {
  const CommitOutcome({
    required this.successCount,
    required this.failedCount,
    required this.cancelled,
  });

  final int successCount;
  final int failedCount;
  final bool cancelled;

  bool get isNoop => successCount == 0 && failedCount == 0 && !cancelled;
}

/// 정리(스와이프) 컨트롤러 — stage → commit → (성공분만) markProcessed 흐름.
///
/// 플랫폼은 전혀 모른다. PhotoService/ProcessedRepository 인터페이스만 사용.
///
/// autoDispose: 정리 화면을 벗어나면(리스너 0) 폐기되고, 재진입 시 [build]가
/// 다시 돌아 미분류 큐를 새로 로드한다. 일반 캐시면 앱 수명 내내 유지되어
/// 재진입 시 스테일 큐/소진 상태가 남는다(QA I-1 회귀 방지).
///
/// Riverpod 3.x에서는 클래스는 [Notifier]를 유지하고 폐기 정책은
/// provider의 `.autoDispose` 수정자로 지정한다.
class SortController extends Notifier<SortState> {
  final List<_SwipeAction> _history = [];

  /// 세션 시작 시점의 미분류 큐 크기(sort_session_complete 의 "남은 미분류수"
  /// 계산 기준). 세션 = 이 autoDispose 컨트롤러 1회 수명.
  int _sessionInitialQueueSize = 0;

  @override
  SortState build() {
    _history.clear();
    // 최초 로드 트리거(비동기).
    Future.microtask(load);
    return const SortState();
  }

  /// 미분류 큐 + 앨범 로드.
  Future<void> load() async {
    state = state.copyWith(status: SortStatus.loading);
    final photo = ref.read(photoServiceProvider);
    try {
      final perm = await photo.ensurePermission();
      if (perm == PhotoPermission.denied) {
        state = state.copyWith(status: SortStatus.denied);
        return;
      }
      final queue = await photo.loadUnclassifiedQueue();
      final albums = await photo.listAlbums();
      _history.clear();
      _sessionInitialQueueSize = queue.length;
      state = SortState(
        status: SortStatus.ready,
        queue: queue,
        albums: albums,
        index: 0,
        pendingCount: photo.pendingAssignments().length,
        canUndo: false,
      );
      // 분석: 정리 세션 시작 — 미분류수 첨부(큐 로드 성공 = 세션 실질 시작).
      ref.read(analyticsServiceProvider).logSortSessionStart(
            unclassifiedCount: queue.length,
          );
    } catch (_) {
      state = state.copyWith(status: SortStatus.error);
    }
  }

  /// 현재 자산을 [album] 으로 배정 예약(stage). 즉시 반영 없음.
  void assignCurrent(AlbumRef album) {
    final asset = state.current;
    if (asset == null) return;
    final photo = ref.read(photoServiceProvider);
    photo.stageAssignment(asset, album);
    _history.add(_SwipeAction(
      index: state.index,
      assetId: asset.id,
      wasAssign: true,
    ));
    state = state.copyWith(
      index: state.index + 1,
      pendingCount: photo.pendingAssignments().length,
      canUndo: true,
    );
  }

  /// 현재 자산 건너뛰기(F-11) — stage 안 함, 다음 회차 재등장.
  void skipCurrent() {
    final asset = state.current;
    if (asset == null) return;
    _history.add(_SwipeAction(
      index: state.index,
      assetId: asset.id,
      wasAssign: false,
    ));
    // 분석: 건너뛰기(속성 없음). 실제 사용자 스킵 액션 시점.
    ref.read(analyticsServiceProvider).logAssetSkipped();
    state = state.copyWith(index: state.index + 1, canUndo: true);
  }

  /// 방금 스와이프 되돌리기(commit 전이라 안전). stage 예약도 취소.
  void undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    final photo = ref.read(photoServiceProvider);
    if (last.wasAssign) {
      photo.unstageAssignment(last.assetId);
    }
    state = state.copyWith(
      index: last.index,
      pendingCount: photo.pendingAssignments().length,
      canUndo: _history.isNotEmpty,
    );
  }

  /// 예약분 배치 확정(commit). 성공분만 markProcessed.
  ///
  /// 반환 [CommitOutcome] 로 화면이 완료 전이/인라인 안내를 결정한다.
  Future<CommitOutcome> commit() async {
    final photo = ref.read(photoServiceProvider);
    final processed = ref.read(processedRepositoryProvider);

    if (photo.pendingAssignments().isEmpty) {
      return const CommitOutcome(
          successCount: 0, failedCount: 0, cancelled: false);
    }

    final analytics = ref.read(analyticsServiceProvider);
    state = state.copyWith(status: SortStatus.committing);
    try {
      final result = await photo.commitAssignments();
      // ★ 성공분만 처리 기록(datamodel §7, 계약 필수).
      for (final s in result.succeeded) {
        await processed.markProcessed(
          assetId: s.finalAssetId,
          albumId: s.albumId,
          mediaType: s.mediaType,
        );
        // 분석: 배정 성공 — SKILL "배정 성공" = stage(예약)가 아니라 commit 으로
        // 시스템에 실제 반영된 성공분. 성공 자산마다 1회, albumId(로컬 UUID) 첨부.
        analytics.logAssetAssigned(albumId: s.albumId);
      }
      // 실패/취소분은 예약 큐에 유지됨. pendingCount 재계산.
      state = state.copyWith(
        status: SortStatus.ready,
        pendingCount: photo.pendingAssignments().length,
        canUndo: false,
      );
      _history.clear();
      final outcome = CommitOutcome(
        successCount: result.succeeded.length,
        failedCount: result.failed.length,
        cancelled: result.cancelled,
      );
      // 분석: 정리 세션 완료 — 완료 화면으로 전이하는 실반영 커밋에서만
      // (취소·noop 은 완료 화면으로 가지 않으므로 제외). 처리수 + 남은 미분류수.
      if (!outcome.cancelled && !outcome.isNoop) {
        final remaining = _sessionInitialQueueSize - outcome.successCount;
        analytics.logSortSessionComplete(
          processedCount: outcome.successCount,
          remainingUnclassified: remaining < 0 ? 0 : remaining,
        );
      }
      return outcome;
    } catch (_) {
      state = state.copyWith(status: SortStatus.ready);
      // 예외는 실패로 간주(예약 유지).
      return CommitOutcome(
        successCount: 0,
        failedCount: photo.pendingAssignments().length,
        cancelled: false,
      );
    }
  }
}

/// autoDispose — 재진입마다 새 인스턴스로 build()→load() 재실행(QA I-1).
final sortControllerProvider =
    NotifierProvider.autoDispose<SortController, SortState>(SortController.new);
