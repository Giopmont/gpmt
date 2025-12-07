import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final image = img.Image(width: 512, height: 512);
  
  // Fill background with transparency (0) or white?
  // Let's do a nice background color for the icon, e.g., dark blue
  img.fill(image, color: img.ColorRgba8(33, 33, 33, 255));

  // Draw a "Banana" (Yellow Crescent)
  // Since we don't have complex curve drawing, we'll approximate with a thick line or polygon
  final yellow = img.ColorRgba8(255, 235, 59, 255);
  
  // Draw curve points
  for (int i = 0; i < 100; i++) {
     int x = 150 + i * 2;
     int y = 350 - (i * i) ~/ 25;
     img.drawCircle(image, x: x, y: y, radius: 40, color: yellow);
  }
  
  // Add "Nano" text?
  // img.drawString(image, font: img.arial48, x: 100, y: 100, string: 'NANO');

  File('assets/icon.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}
