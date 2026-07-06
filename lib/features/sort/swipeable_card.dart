import 'package:flutter/material.dart';

enum SwipeDir { left, right, up }

/// 큰 썸네일 카드 + 스와이프 제스처.
///
/// 스와이프는 "예약 요청"일 뿐이며 실제 큐 전진은 부모의 상태 변경으로 일어난다.
/// (오른쪽=배정 예약 모달 / 왼쪽=건너뛰기 / 위=최근 앨범 예약 — 00_decisions 잠정안)
/// 방향 감지 후에는 카드를 가운데로 스냅백하고 콜백만 호출한다(모달 취소 시 안전).
class SwipeableCard extends StatefulWidget {
  const SwipeableCard({
    super.key,
    required this.child,
    required this.onSwipe,
    this.onTap,
    this.threshold = 90,
  });

  final Widget child;
  final void Function(SwipeDir dir) onSwipe;
  final VoidCallback? onTap;
  final double threshold;

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard>
    with SingleTickerProviderStateMixin {
  Offset _drag = Offset.zero;
  late final AnimationController _controller;
  Animation<Offset>? _snap;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        if (_snap != null) setState(() => _drag = _snap!.value);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapBack() {
    _snap = Tween(begin: _drag, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward(from: 0);
  }

  void _onPanEnd(DragEndDetails _) {
    final dx = _drag.dx;
    final dy = _drag.dy;
    SwipeDir? dir;
    if (dx > widget.threshold && dx.abs() > dy.abs()) {
      dir = SwipeDir.right;
    } else if (dx < -widget.threshold && dx.abs() > dy.abs()) {
      dir = SwipeDir.left;
    } else if (dy < -widget.threshold) {
      dir = SwipeDir.up;
    }
    _snapBack();
    if (dir != null) widget.onSwipe(dir);
  }

  /// 드래그 방향에 따른 힌트 라벨.
  Widget? _hint(BuildContext context) {
    final theme = Theme.of(context);
    if (_drag.dx > 40) {
      return _HintBadge(
        label: '배정',
        color: theme.colorScheme.primary,
        onColor: theme.colorScheme.onPrimary,
        icon: Icons.folder_open,
        alignment: Alignment.topRight,
      );
    }
    if (_drag.dx < -40) {
      return _HintBadge(
        label: '나중에',
        color: theme.colorScheme.outline,
        icon: Icons.schedule,
        alignment: Alignment.topLeft,
      );
    }
    if (_drag.dy < -40) {
      return _HintBadge(
        label: '최근 앨범',
        color: theme.colorScheme.tertiary,
        onColor: theme.colorScheme.onTertiary,
        icon: Icons.bookmark_added,
        alignment: Alignment.topCenter,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final angle = (_drag.dx / 1200).clamp(-0.1, 0.1);
    final hint = _hint(context);
    return GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: (d) => setState(() => _drag += d.delta),
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              if (hint != null) Positioned.fill(child: hint),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintBadge extends StatelessWidget {
  const _HintBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.alignment,
    this.onColor = Colors.white,
  });

  final String label;
  final Color color;
  final Color onColor;
  final IconData icon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: onColor, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: onColor, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
