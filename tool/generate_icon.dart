import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const int size = 1024; // High res for launcher icons
  final image = img.Image(width: size, height: size);
  
  // Colors
  final bgCol = img.ColorRgba8(40, 44, 52, 255); // Dark Grey/Blue
  final folderCol = img.ColorRgba8(255, 193, 7, 255); // Amber/Gold Folder
  final folderDarkCol = img.ColorRgba8(255, 160, 0, 255); // Darker Amber
  final lockBodyCol = img.ColorRgba8(189, 189, 189, 255); // Silver
  final lockShackleCol = img.ColorRgba8(66, 66, 66, 255); // Dark Grey
  final textCol = img.ColorRgba8(255, 255, 255, 255); // White
  final zipperCol = img.ColorRgba8(100, 100, 100, 255);
  
  // 1. Background (Rounded Rect / Circle-ish)
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0)); // Transparent start
  img.fillCircle(image, x: size ~/ 2, y: size ~/ 2, radius: size ~/ 2, color: bgCol);

  // 2. Folder Shape
  // Main body
  int margin = 200;
  img.fillRect(image, x1: margin, y1: 300, x2: size - margin, y2: size - 250, color: folderCol, radius: 40);
  // Tab
  img.fillRect(image, x1: margin, y1: 220, x2: margin + 250, y2: 300, color: folderDarkCol, radius: 20);

  // 3. Zipper (Vertical line down the middle)
  int centerX = size ~/ 2;
  for (int y = 300; y < size - 250; y += 40) {
    // Zipper teeth
    img.fillRect(image, x1: centerX - 15, y1: y, x2: centerX + 15, y2: y + 20, color: zipperCol);
  }

  // 4. Padlock (Centering it over the zipper/folder)
  int lockW = 200;
  int lockH = 160;
  int lockX = centerX - (lockW ~/ 2);
  int lockY = 550; // Lower on the folder
  
  // Shackle (Arc approximation)
  int shackleR = 70;
  int shackleThick = 25;
  img.drawCircle(image, x: centerX, y: lockY, radius: shackleR, color: lockShackleCol);
  img.fillCircle(image, x: centerX, y: lockY, radius: shackleR - shackleThick, color: folderCol); // Mask inner
  // Clean up bottom half of circle to make it a U shape (simply redraw folder rect area over it? No, transparency is hard here)
  // Instead, just draw the body on top.

  // Lock Body
  img.fillRect(image, x1: lockX, y1: lockY, x2: lockX + lockW, y2: lockY + lockH, color: lockBodyCol, radius: 20);
  // Keyhole
  img.fillCircle(image, x: centerX, y: lockY + (lockH ~/ 2), radius: 20, color: img.ColorRgba8(40, 40, 40, 255));
  img.fillRect(image, x1: centerX - 5, y1: lockY + (lockH ~/ 2), x2: centerX + 5, y2: lockY + (lockH ~/ 2) + 40, color: img.ColorRgba8(40, 40, 40, 255));


  // 5. Text "GPMT"
  // Since we don't have large vector fonts, we'll draw it pixel-style or composed of shapes? 
  // Actually, 'image' package has arial48, but 48px is too small for a 1024px icon.
  // We will manually draw block letters "G P M T" on the Folder Tab or above.
  
  // Draw GPMT on the Folder Tab area
  // G
  _drawBlockChar(image, 230, 240, 'G', textCol);
  // P
  _drawBlockChar(image, 290, 240, 'P', textCol);
  // M
  _drawBlockChar(image, 350, 240, 'M', textCol);
  // T
  _drawBlockChar(image, 410, 240, 'T', textCol);

  // Save
  File('assets/icon.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

void _drawBlockChar(img.Image image, int x, int y, String char, img.Color color) {
  int w = 10; // stroke width
  int h = 40; // char height
  int cw = 30; // char width
  
  if (char == 'G') {
    img.fillRect(image, x1: x, y1: y, x2: x+cw, y2: y+w, color: color); // Top
    img.fillRect(image, x1: x, y1: y, x2: x+w, y2: y+h, color: color); // Left
    img.fillRect(image, x1: x, y1: y+h-w, x2: x+cw, y2: y+h, color: color); // Bottom
    img.fillRect(image, x1: x+cw-w, y1: y+(h~/2), x2: x+cw, y2: y+h, color: color); // Right bottom
    img.fillRect(image, x1: x+(cw~/2), y1: y+(h~/2), x2: x+cw, y2: y+(h~/2)+w, color: color); // Middle in
  } else if (char == 'P') {
    img.fillRect(image, x1: x, y1: y, x2: x+w, y2: y+h, color: color); // Left
    img.fillRect(image, x1: x, y1: y, x2: x+cw, y2: y+w, color: color); // Top
    img.fillRect(image, x1: x+cw-w, y1: y, x2: x+cw, y2: y+(h~/2), color: color); // Right
    img.fillRect(image, x1: x, y1: y+(h~/2), x2: x+cw, y2: y+(h~/2)+w, color: color); // Middle
  } else if (char == 'M') {
    img.fillRect(image, x1: x, y1: y, x2: x+w, y2: y+h, color: color); // Left
    img.fillRect(image, x1: x+cw-w, y1: y, x2: x+cw, y2: y+h, color: color); // Right
    img.drawLine(image, x1: x, y1: y, x2: x+(cw~/2), y2: y+(h~/2), color: color, thickness: w.toDouble()); // Diag 1
    img.drawLine(image, x1: x+cw, y1: y, x2: x+(cw~/2), y2: y+(h~/2), color: color, thickness: w.toDouble()); // Diag 2
  } else if (char == 'T') {
    img.fillRect(image, x1: x, y1: y, x2: x+cw, y2: y+w, color: color); // Top
    img.fillRect(image, x1: x+(cw~/2)-(w~/2), y1: y, x2: x+(cw~/2)+(w~/2), y2: y+h, color: color); // Middle
  }
}
