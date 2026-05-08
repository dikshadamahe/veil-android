import 'package:flutter/widgets.dart';

enum WindowClass { compact, medium, expanded }

enum HandsetDensity { small, regular, large }

WindowClass windowClass(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;

  if (width < 600) {
    return WindowClass.compact;
  }

  if (width < 960) {
    return WindowClass.medium;
  }

  return WindowClass.expanded;
}

int gridCols(BuildContext context) {
  switch (windowClass(context)) {
    case WindowClass.compact:
      return 2;
    case WindowClass.medium:
      return 3;
    case WindowClass.expanded:
      return 4;
  }
}

bool isTV(BuildContext context) {
  return windowClass(context) == WindowClass.expanded;
}

HandsetDensity handsetDensity(BuildContext context) {
  final Size size = MediaQuery.sizeOf(context);
  final double shortestSide = size.shortestSide;

  if (shortestSide < 380) {
    return HandsetDensity.small;
  }

  if (shortestSide < 460) {
    return HandsetDensity.regular;
  }

  return HandsetDensity.large;
}

bool isSmallHandset(BuildContext context) {
  return handsetDensity(context) == HandsetDensity.small;
}
