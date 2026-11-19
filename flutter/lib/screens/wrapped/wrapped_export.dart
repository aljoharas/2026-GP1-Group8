// Saving and sharing Gaming Wrapped cards as images.
//
// A card is never captured from the live screen. Each one is built again in an
// off-screen OverlayEntry at a fixed 9:16 story size (360x640, the size the
// golden tests check), with animations disabled so WrappedCardState shows its
// final frame (count-ups finished, loops at rest) and with text scaling off so
// the image doesn't depend on the user's settings. Its images are loaded
// first, then the boundary is rendered at 3x into a 1080x1920 PNG. The story
// chrome (progress bar, wordmark, close button) lives in WrappedScreen, so it
// is never part of the image. Cards are captured one at a time and each image
// is released as soon as it is encoded.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import 'wrapped_card.dart';

/// The logical size a card is laid out at for export: 9:16.
const kWrappedExportLogicalSize = Size(360, 640);

/// The exported image size, in pixels.
const kWrappedExportPixelSize = Size(1080, 1920);

/// Pixel ratio that turns the logical size into the pixel size.
final double kWrappedExportPixelRatio = kWrappedExportPixelSize.width / kWrappedExportLogicalSize.width;

/// How long to wait for a card's images (and extra data) before capturing it
/// with placeholders instead.
const kWrappedExportLoadTimeout = Duration(seconds: 8);

/// Covers CachedNetworkImage's 200 ms fade-in for an image that finished
/// loading after the card was built.
const _fadeAllowance = Duration(milliseconds: 300);

/// Renders [card] off-screen at story size and returns it as PNG bytes.
///
/// [context] must be below an Overlay (any route's context is). A slow or
/// failed image never blocks for longer than [loadTimeout]; it is drawn as
/// the card's usual placeholder.
Future<Uint8List> captureWrappedCard(
  BuildContext context,
  Widget card, {
  Duration loadTimeout = kWrappedExportLoadTimeout,
}) async {
  final overlay = Overlay.of(context);
  final boundaryKey = GlobalKey();
  final media = MediaQuery.of(context).copyWith(
    size: kWrappedExportLogicalSize,
    devicePixelRatio: kWrappedExportPixelRatio,
    padding: EdgeInsets.zero,
    viewPadding: EdgeInsets.zero,
    viewInsets: EdgeInsets.zero,
    textScaler: TextScaler.noScaling,
    boldText: false,
    disableAnimations: true,
  );

  // Images already in memory paint on the first frame, with no fade.
  if (card case WrappedCard(:final imageUrls)) {
    await _precache(imageUrls, context, loadTimeout);
  }
  if (!context.mounted) throw const WrappedExportException('The screen was closed.');

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far off to the left: laid out and painted, never seen or tapped.
      left: -4 * kWrappedExportLogicalSize.width,
      top: 0,
      width: kWrappedExportLogicalSize.width,
      height: kWrappedExportLogicalSize.height,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: InheritedTheme.captureAll(
            context,
            MediaQuery(
              data: media,
              child: Material(
                type: MaterialType.transparency,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: WrappedPageScope(active: true, child: card),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    final boundaryContext = boundaryKey.currentContext;
    if (boundaryContext == null || !boundaryContext.mounted) {
      throw const WrappedExportException('The card could not be built.');
    }

    // Data a card loads after building (the intro's extra covers, the player
    // type's photo), then any images that brought in.
    if (_cardState(boundaryContext)?.exportReady case final ready?) {
      await ready.timeout(loadTimeout, onTimeout: () {}).catchError((_) {});
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!boundaryContext.mounted) throw const WrappedExportException('The screen was closed.');
    final pending = _networkImageUrls(boundaryContext).where((url) => !_isCached(url)).toList();
    if (pending.isNotEmpty) {
      await _precache(pending, boundaryContext, loadTimeout);
      await Future<void>.delayed(_fadeAllowance);
    }
    await WidgetsBinding.instance.endOfFrame;

    if (!boundaryContext.mounted) throw const WrappedExportException('The screen was closed.');
    final boundary = boundaryContext.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: kWrappedExportPixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const WrappedExportException('The image could not be encoded.');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

class WrappedExportException implements Exception {
  final String message;

  const WrappedExportException(this.message);

  @override
  String toString() => message;
}

Future<void> _precache(Iterable<String> urls, BuildContext context, Duration timeout) {
  // precacheWrappedImage swallows load errors, so this only ever times out.
  return Future.wait([
    for (final url in urls) precacheWrappedImage(url, context),
  ]).timeout(timeout, onTimeout: () => const <void>[]);
}

bool _isCached(String url) =>
    PaintingBinding.instance.imageCache.containsKey(CachedNetworkImageProvider(url));

WrappedCardState? _cardState(BuildContext context) {
  WrappedCardState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is WrappedCardState) {
      found = element.state as WrappedCardState;
      return;
    }
    element.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  return found;
}

/// Every network image URL currently in the tree under [context].
Set<String> _networkImageUrls(BuildContext context) {
  final urls = <String>{};
  void visit(Element element) {
    if (element.widget case CachedNetworkImage(:final imageUrl)) urls.add(imageUrl);
    element.visitChildElements(visit);
  }

  context.visitChildElements(visit);
  return urls;
}

// --- Save & share ------------------------------------------------------------------

String _fileName(int year, int index) => 'loadout_endgame_${year}_${(index + 1).toString().padLeft(2, '0')}';

/// The gallery file name: unique per save, so the media scan below finds this
/// save's file and not an earlier one. "loadout_endgame_2026_04_20261119_215301".
String _galleryName(int year, int index, DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_fileName(year, index)}_${at.year}${two(at.month)}${two(at.day)}_${two(at.hour)}${two(at.minute)}${two(at.second)}';
}

const _permissionMessage = 'Allow Loadout to add photos in Settings to save your cards.';

// TODO(wrapped-save): remove the [wrapped-save] debugPrint logging once gallery
// saving is confirmed on Android 7-10 devices.
void _log(String message) => debugPrint('[wrapped-save] $message');

/// Asks for gallery access only when the user saves. False if denied.
Future<bool> _ensureGalleryAccess() async {
  final has = await Gal.hasPermission();
  _log('hasPermission: $has');
  if (has) return true;
  final granted = await Gal.requestPermission();
  _log('requestPermission: $granted');
  return granted;
}

/// Android side of the save check (MainActivity.kt).
const _mediaScan = MethodChannel('loadout/media_scan');

/// Saves [bytes] with gal, then checks the result. On Android 7-10 gal's
/// MediaStore row has no size or dimensions until the file is scanned, and
/// galleries hide it, so the file is found, checked and scanned here; a
/// missing file or failed scan is an error, never "Saved".
Future<void> _saveToGallery(Uint8List bytes, String name) async {
  _log('saving $name: ${bytes.length} bytes');
  try {
    await Gal.putImageBytes(bytes, name: name);
  } catch (e) {
    _log('gal failed for $name: $e');
    rethrow;
  }
  _log('gal finished for $name');
  if (defaultTargetPlatform != TargetPlatform.android) return;

  final result = await _mediaScan.invokeMapMethod<String, Object?>('scanSavedImage', {'name': name});
  _log('media scan for $name: $result');
  switch (result?['status']) {
    case 'scanned' || 'not_needed':
      return;
    case 'missing':
      throw const WrappedSaveException('The image was not found after saving.');
    default:
      throw const WrappedSaveException('The image was saved but the gallery could not index it.');
  }
}

class WrappedSaveException implements Exception {
  final String message;

  const WrappedSaveException(this.message);

  @override
  String toString() => message;
}

String _saveErrorMessage(Object error) => switch (error) {
  GalException(type: GalExceptionType.permissionDenied) => _permissionMessage,
  GalException(type: GalExceptionType.notEnoughSpace) => 'Not enough storage to save the image.',
  GalException(:final type) => "Couldn't save the image (${type.name}).",
  WrappedExportException(:final message) => "Couldn't create the image. $message",
  WrappedSaveException(:final message) => "Couldn't save the image. $message",
  _ => "Couldn't save the image.",
};

/// The share/save button shown in the corner of every card. Opens a sheet
/// with "Save to gallery", "Share" and "Save all cards".
class WrappedExportButton extends StatefulWidget {
  final int year;
  final List<Widget> cards;
  final int current;

  const WrappedExportButton({super.key, required this.year, required this.cards, required this.current});

  @override
  State<WrappedExportButton> createState() => _WrappedExportButtonState();
}

enum _ExportAction { save, share, saveAll }

class _WrappedExportButtonState extends State<WrappedExportButton> {
  bool _busy = false;

  Future<void> _openMenu() async {
    final action = await showModalBottomSheet<_ExportAction>(
      context: context,
      backgroundColor: const Color(0xFF15151C),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Colors.white),
              title: const Text('Save to gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, _ExportAction.save),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, _ExportAction.share),
            ),
            if (widget.cards.length > 1)
              ListTile(
                leading: const Icon(Icons.collections_rounded, color: Colors.white),
                title: Text('Save all cards (${widget.cards.length})', style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, _ExportAction.saveAll),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ExportAction.save:
        await _run(() => _save(widget.current));
      case _ExportAction.share:
        await _run(() => _share(widget.current));
      case _ExportAction.saveAll:
        await _run(() => _saveAll(0));
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: retry == null ? null : SnackBarAction(label: 'Retry', onPressed: retry),
        ),
      );
  }

  Future<void> _save(int index) async {
    final card = widget.cards[index];
    final year = widget.year;
    try {
      if (!await _ensureGalleryAccess()) {
        _message(_permissionMessage, retry: () => _run(() => _save(index)));
        return;
      }
      if (!mounted) return;
      final bytes = await captureWrappedCard(context, card);
      await _saveToGallery(bytes, _galleryName(year, index, DateTime.now()));
      _message('Saved to your gallery.');
    } catch (e) {
      _log('save failed: $e');
      _message(_saveErrorMessage(e), retry: () => _run(() => _save(index)));
    }
  }

  Future<void> _share(int index) async {
    final card = widget.cards[index];
    final name = '${_fileName(widget.year, index)}.png';
    // The share sheet anchors to the button on iPad (required there).
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final bytes = await captureWrappedCard(context, card);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [name],
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      final message = e is WrappedExportException ? "Couldn't create the image. ${e.message}" : "Couldn't share the image.";
      _message(message, retry: () => _run(() => _share(index)));
    }
  }

  /// Saves cards [from] onwards, one at a time, with a progress dialog.
  /// A failure stops there; Retry continues from that card.
  Future<void> _saveAll(int from) async {
    final cards = widget.cards;
    final year = widget.year;
    try {
      if (!await _ensureGalleryAccess()) {
        _message(_permissionMessage, retry: () => _run(() => _saveAll(from)));
        return;
      }
    } catch (e) {
      _message(_saveErrorMessage(e), retry: () => _run(() => _saveAll(from)));
      return;
    }
    if (!mounted) return;

    final progress = ValueNotifier(from);
    var cancelled = false;
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: _SaveAllDialog(
            progress: progress,
            total: cards.length,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );

    var index = from;
    Object? error;
    final startedAt = DateTime.now();
    try {
      for (; index < cards.length && !cancelled; index++) {
        progress.value = index;
        if (!mounted) return;
        final bytes = await captureWrappedCard(context, cards[index]);
        await _saveToGallery(bytes, _galleryName(year, index, startedAt));
        // bytes goes out of scope here, so only one image is held at a time
      }
    } catch (e) {
      _log('save all failed at card ${index + 1}: $e');
      error = e;
    } finally {
      // progress isn't disposed: the dialog still reads it while it animates out
      if (navigator.mounted) navigator.pop();
    }

    if (error != null) {
      final failedAt = index;
      _message(
        'Saved $failedAt of ${cards.length}. ${_saveErrorMessage(error)}',
        retry: () => _run(() => _saveAll(failedAt)),
      );
    } else if (cancelled) {
      _message('Stopped. Saved $index of ${cards.length} cards.');
    } else {
      _message('All ${cards.length} cards saved to your gallery.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : IconButton(
                tooltip: 'Save or share',
                padding: EdgeInsets.zero,
                iconSize: 18,
                color: Colors.white,
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: _openMenu,
              ),
      ),
    );
  }
}

class _SaveAllDialog extends StatelessWidget {
  final ValueListenable<int> progress;
  final int total;
  final VoidCallback onCancel;

  const _SaveAllDialog({required this.progress, required this.total, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF15151C),
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (context, done, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: done / total, color: Colors.white, backgroundColor: Colors.white24),
            const SizedBox(height: 16),
            Text('Saving ${done + 1} of $total…', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Stop', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
