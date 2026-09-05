import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';
import 'sheets.dart';

/// Camera or gallery, asked in plain words before the picker opens.
///
/// The gallery on a fresh phone (or an emulator) is empty and the system
/// picker then shows a blank screen that looks broken; the camera always
/// has something to give. Returns null when the sheet is dismissed.
Future<ImageSource?> choosePhotoSource(BuildContext context) {
  return showLbmSheet<ImageSource>(context, (sheetContext) {
    final c = sheetContext.c;
    return LbmSheet(
      children: [
        Text(
          'Add a photo',
          style: LbmText.display.copyWith(fontSize: 19, color: c.ink),
        ),
        const SizedBox(height: 6),
        ListRow(
          leading: Icon(Icons.photo_camera_outlined, color: c.skyDeep),
          title: const Text('Take a photo'),
          onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          divided: true,
        ),
        ListRow(
          leading: Icon(Icons.photo_library_outlined, color: c.skyDeep),
          title: const Text('Choose from your photos'),
          onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
        ),
      ],
    );
  });
}

/// The content type a picked file carries, guessed from its name when the
/// platform did not say.
String pickedContentType(XFile file) =>
    file.mimeType ??
    (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
