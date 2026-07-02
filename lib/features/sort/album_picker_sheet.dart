import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/album_ref.dart';
import '../../core/providers.dart';
import '../shared/asset_thumbnail.dart';

/// 앨범 선택 모달(F-04). 기존 앨범 선택 또는 인라인 새 앨범 생성.
///
/// 선택되면 [AlbumRef] 로 pop, 닫으면 null(배정 취소).
Future<AlbumRef?> showAlbumPicker(BuildContext context) {
  return showModalBottomSheet<AlbumRef>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AlbumPickerSheet(),
  );
}

class _AlbumPickerSheet extends ConsumerStatefulWidget {
  const _AlbumPickerSheet();

  @override
  ConsumerState<_AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends ConsumerState<_AlbumPickerSheet> {
  late Future<List<AlbumRef>> _albumsFuture;
  bool _creating = false;
  final _nameController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _albumsFuture = ref.read(photoServiceProvider).listAlbums();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createAlbum() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final album = await ref.read(photoServiceProvider).createAlbum(name);
      if (mounted) Navigator.of(context).pop(album);
    } catch (_) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = '앨범을 만들지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('어느 앨범으로 옮길까요?',
                  style: theme.textTheme.titleLarge),
            ),
            // 새 앨범 생성 인라인 입력.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _createAlbum(),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.create_new_folder_outlined),
                        hintText: '새 앨범 이름',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _creating ? null : _createAlbum,
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('만들기'),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<AlbumRef>>(
                future: _albumsFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('앨범을 불러오지 못했어요.'),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _albumsFuture = ref
                                  .read(photoServiceProvider)
                                  .listAlbums();
                            }),
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    );
                  }
                  final albums = snap.data ?? const [];
                  if (albums.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('첫 앨범을 위에서 만들어보세요.'),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: albums.length,
                    itemBuilder: (context, i) {
                      final album = albums[i];
                      return ListTile(
                        leading: SizedBox(
                          width: 48,
                          height: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: album.coverAssetId != null
                                ? AssetThumbnail(
                                    assetId: album.coverAssetId!,
                                    size: 100,
                                    showVideoBadge: false,
                                  )
                                : Container(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: Icon(Icons.photo_album_outlined,
                                        color: theme.colorScheme.outline),
                                  ),
                          ),
                        ),
                        title: Text(album.name),
                        onTap: () => Navigator.of(context).pop(album),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
