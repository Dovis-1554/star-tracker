import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

/// 无封面时按标题程序化生成占位海报。
///
/// 配色由标题 hash 决定，同一标题在任何设备上得到同一张图，
/// 因此生成结果不需要同步——这是绕开坚果云流量限制的关键。
abstract final class CoverGenerator {
  static const double _width = 300;
  static const double _height = 450; // 2:3

  static Future<Directory> _coverDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'covers'));
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  static Future<String> coverPathFor(String id) async {
    final dir = await _coverDir();
    return p.join(dir.path, '$id.png');
  }

  /// 生成并落盘，返回文件路径。标题变化时应重新调用以覆盖旧图。
  static Future<String> generate({
    required String id,
    required String title,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    CoverPainter(title: title).paint(canvas, const Size(_width, _height));
    final picture = recorder.endRecording();
    final image = await picture.toImage(_width.toInt(), _height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('封面生成失败：$title');

    final path = await coverPathFor(id);
    await File(path).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return path;
  }

  /// 色相由标题决定，保证确定性。
  @visibleForTesting
  static Color colorFor(String title) {
    final hue = (title.hashCode & 0xFFFF) % 360.0;
    return HSLColor.fromAHSL(1.0, hue, 0.42, 0.46).toColor();
  }
}

class CoverPainter extends CustomPainter {
  const CoverPainter({required this.title});

  final String title;

  @override
  void paint(Canvas canvas, Size size) {
    // 封面只写剧名本体，不写季号——同剧各季共用一张封面。
    final shown = TitleNames.baseNameOf(title).trim();
    final bg = CoverGenerator.colorFor(shown);
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);

    final text = shown.isEmpty ? '?' : shown;
    final maxWidth = size.width * 0.78;

    // 从大到小试字号，直到能放下
    var fontSize = size.width * 0.22;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            height: 1.25,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 4,
      )..layout(maxWidth: maxWidth);
      if (tp.didExceedMaxLines == false || fontSize <= 12) break;
      fontSize -= 2;
    }

    final offset = Offset(
      (size.width - maxWidth) / 2,
      (size.height - tp.height) / 2,
    );
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CoverPainter oldDelegate) => oldDelegate.title != title;
}

/// 封面墙里用的封面组件：优先本地生成图，失败时降级为即时绘制。
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({
    super.key,
    required this.title,
    this.path,

    /// 固定宽度；传 null 表示撑满父容器（封面墙格子宽度不固定时用）。
    this.width = 77,
  });

  final String title;
  final String? path;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final file = path;
    final w = width;
    final child = file != null && File(file).existsSync()
        ? Image.file(File(file), fit: BoxFit.cover)
        : CustomPaint(painter: CoverPainter(title: title));

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: w == null
          ? SizedBox.expand(child: child)
          : SizedBox(
              width: w,
              height: w / AppTheme.coverAspect,
              child: child,
            ),
    );
  }
}
