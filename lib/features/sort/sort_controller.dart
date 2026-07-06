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
    this.deletedCount = 0,
    this.canUndo = false,
  });

  final SortStatus status;
  final List<AssetRef> queue;
  final List<AlbumRef> albums;
  final int index;
  final int pendingCount;

  /// 이번 세션에서 즉시 삭제에 성공한 자산 수(D5). 삭제는 stage→commit 이 아니라
  /// 탭 즉시 실행되므로 배정 예약(pendingCount)과 독립적인 세션 누계로 유지되며,
  /// 완료 화면 총계·분해에 합산된다.
  final int deletedCount;

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
    int? deletedCount,
    bool? canUndo,
  }) {
    return SortState(
      status: status ?? this.status,
      queue: queue ?? this.queue,
      albums: albums ?? this.albums,
      index: index ?? this.index,
      pendingCount: pendingCount ?? this.pendingCount,
      deletedCount: deletedCount ?? this.deletedCount,
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
    this.deletedCount = 0,
  });

  final int successCount;
  final int failedCount;
  final bool cancelled;

  /// 이번 세션에서 즉시 삭제에 성공한 자산 수(D5). 배정 commit 과 무관하게 세션
  /// 누계로 전달되며, 완료 화면 총계·분해에 쓰인다.
  final int deletedCount;

  /// 완료 화면으로 보여줄 실반영이 하나도 없는 상태. 삭제분도 성취이므로 포함한다
  /// (삭제만 한 세션도 완료 화면으로 가야 하기 때문).
  bool get isNoop =>
      successCount == 0 && failedCount == 0 && deletedCount == 0 && !cancelled;
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

  /// 현재 자산을 즉시·영구 삭제(D5, F-14c'). OS 동의창을 포함하며, 배정과 달리
  /// stage→commit 이 아니라 탭 즉시 실행된다.
  ///
  /// 반환 `true` = 삭제 성공(카드 제거·다음 카드로 진행), `false` = 취소 또는 실패
  /// (카드 유지). 호출측(화면)은 `false` 면 "삭제하지 못했어요" 스낵을 띄운다(D5-6).
  ///
  /// **history 에 기록하지 않는다** — 삭제는 영구·즉시라 앱 내 되돌리기가 없다
  /// (OS 동의창이 유일 확인 지점, §0.2). 따라서 [undo] 는 삭제에 영향을 주지 않는다.
  Future<bool> deleteCurrent() async {
    final asset = state.current;
    if (asset == null) return false;
    final photo = ref.read(photoServiceProvider);
    final ok = await photo.deleteAsset(asset);
    if (!ok) return false;
    // 삭제 성공: streak 원천에 기록 + 분석 + 세션 누계·카드 진행.
    // markProcessed 는 호출하지 않는다(삭제 자산은 ProcessedAsset 미기록, DEL-4').
    // 서비스가 _pending·스캔 캐시 정리는 내부에서 수행하므로 여기선 불필요(§G.3).
    await ref.read(deletionRepositoryProvider).logDeletion();
    ref.read(analyticsServiceProvider).logAssetDeleted();
    state = state.copyWith(
      index: state.index + 1,
      deletedCount: state.deletedCount + 1,
    );
    return true;
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

    final analytics = ref.read(analyticsServiceProvider);

    if (photo.pendingAssignments().isEmpty) {
      // 배정 예약은 없다. 단, 세션 삭제분이 있으면 "삭제만 한 세션"으로 완료
      // 화면에 가야 하므로 outcome 에 deletedCount 를 실어 보내고 완료 이벤트도
      // 남긴다(§0.2, DEL-8). 삭제도 없으면 순수 no-op.
      final outcome = CommitOutcome(
        successCount: 0,
        failedCount: 0,
        cancelled: false,
        deletedCount: state.deletedCount,
      );
      if (!outcome.isNoop) {
        final remaining = _sessionInitialQueueSize - outcome.deletedCount;
        analytics.logSortSessionComplete(
          processedCount: 0,
          remainingUnclassified: remaining < 0 ? 0 : remaining,
          deletedCount: outcome.deletedCount,
        );
      }
      return outcome;
    }

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
        deletedCount: state.deletedCount,
      );
      // 분석: 정리 세션 완료 — 완료 화면으로 전이하는 실반영 커밋에서만
      // (취소·noop 은 완료 화면으로 가지 않으므로 제외). 처리수 + 남은 미분류수 +
      // 세션 삭제수(D5). 삭제분도 큐를 떠났으므로 remaining 에서 함께 차감한다.
      if (!outcome.cancelled && !outcome.isNoop) {
        final remaining = _sessionInitialQueueSize -
            outcome.successCount -
            outcome.deletedCount;
        analytics.logSortSessionComplete(
          processedCount: outcome.successCount,
          remainingUnclassified: remaining < 0 ? 0 : remaining,
          deletedCount: outcome.deletedCount,
        );
      }
      return outcome;
    } catch (_) {
      state = state.copyWith(status: SortStatus.ready);
      // 예외는 실패로 간주(예약 유지). 세션 삭제분은 이미 반영됐으므로 함께 전달.
      return CommitOutcome(
        successCount: 0,
        failedCount: photo.pendingAssignments().length,
        cancelled: false,
        deletedCount: state.deletedCount,
      );
    }
  }
}

/// autoDispose — 재진입마다 새 인스턴스로 build()→load() 재실행(QA I-1).
final sortControllerProvider =
    NotifierProvider.autoDispose<SortController, SortState>(SortController.new);
