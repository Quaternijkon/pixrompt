import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';

import '../app/pixrompt_controller.dart';

class PickedImageLoader {
  const PickedImageLoader({
    required this.name,
    required this.load,
  });

  final String name;
  final Future<PickedImageBytes> Function() load;
}

class PixromptFileActions {
  const PixromptFileActions();

  Future<List<PickedImageLoader>> pickImageLoaders() async {
    final files = await ImagePicker().pickMultiImage(
      requestFullMetadata: false,
    );
    return [
      for (final file in files)
        PickedImageLoader(
          name: file.name,
          load: () async {
            final bytes = await file.readAsBytes();
            final decoded = image_lib.decodeImage(bytes);
            return PickedImageBytes(
              name: file.name,
              bytes: Uint8List.fromList(bytes),
              width: decoded?.width ?? 0,
              height: decoded?.height ?? 0,
            );
          },
        ),
    ];
  }

  Future<List<PickedImageBytes>> pickImages() async {
    final loaders = await pickImageLoaders();
    final picked = <PickedImageBytes>[];
    for (final image
        in await Future.wait(loaders.map((loader) => loader.load()))) {
      if (image.bytes.isNotEmpty) picked.add(image);
    }
    return picked;
  }

  Future<String?> pickBackupJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  Future<void> saveBackupJson(String jsonText) {
    final date =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return FileSaver.instance.saveFile(
      name: 'pixrompt-backup-$date',
      bytes: Uint8List.fromList(utf8.encode(jsonText)),
      ext: 'json',
      mimeType: MimeType.json,
    );
  }
}
