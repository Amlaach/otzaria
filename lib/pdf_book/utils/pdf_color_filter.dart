import 'package:flutter/material.dart';

/// צבע שמצויר בתוך שכבת ה-PDF יתהפך שוב במצב כהה.
Color pdfColorBeforeFilter(Color color, Brightness brightness) {
  if (brightness != Brightness.dark) return color;
  return Color.from(
    alpha: color.a,
    red: 1.0 - color.r,
    green: 1.0 - color.g,
    blue: 1.0 - color.b,
  );
}
