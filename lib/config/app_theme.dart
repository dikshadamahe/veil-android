import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Base tokens: black
  static const Color blackC50 = Color(0xFF000000);
  static const Color blackC75 = Color(0xFF030303);
  static const Color blackC80 = Color(0xFF080808);
  static const Color blackC100 = Color(0xFF0D0D0D);
  static const Color blackC125 = Color(0xFF141414);
  static const Color blackC150 = Color(0xFF1A1A1A);
  static const Color blackC200 = Color(0xFF262626);
  static const Color blackC250 = Color(0xFF333333);
  static const Color transparent = Color(0x00000000);

  // Base tokens: white
  static const Color white = Color(0xFFFFFFFF);

  // Base tokens: semantic
  static const Color semanticRedC100 = Color(0xFFF46E6E);
  static const Color semanticRedC200 = Color(0xFFE44F4F);
  static const Color semanticRedC300 = Color(0xFFD74747);
  static const Color semanticRedC400 = Color(0xFFB43434);

  static const Color semanticGreenC100 = Color(0xFF60D26A);
  static const Color semanticGreenC200 = Color(0xFF40B44B);
  static const Color semanticGreenC300 = Color(0xFF31A33C);
  static const Color semanticGreenC400 = Color(0xFF237A2B);

  static const Color semanticSilverC100 = Color(0xFFDEDEDE);
  static const Color semanticSilverC200 = Color(0xFFB6CAD7);
  static const Color semanticSilverC300 = Color(0xFF8EA3B0);
  static const Color semanticSilverC400 = Color(0xFF617A8A);

  static const Color semanticYellowC100 = Color(0xFFFFF599);
  static const Color semanticYellowC200 = Color(0xFFFCEC61);
  static const Color semanticYellowC300 = Color(0xFFD8C947);
  static const Color semanticYellowC400 = Color(0xFFAFA349);

  static const Color semanticRoseC100 = Color(0xFFDB3D61);
  static const Color semanticRoseC200 = Color(0xFF8A293B);
  static const Color semanticRoseC300 = Color(0xFF812435);
  static const Color semanticRoseC400 = Color(0xFF701B2B);

  // Semantic aliases
  static const Color success = semanticGreenC100;
  static const Color error = semanticRedC100;
  static const Color warning = semanticYellowC100;

  // Base tokens: blue
  static const Color blueC50 = Color(0xFFCCCCD6);
  static const Color blueC100 = Color(0xFFA2A2A2);
  static const Color blueC200 = Color(0xFF868686);
  static const Color blueC300 = Color(0xFF646464);
  static const Color blueC400 = Color(0xFF4E4E4E);
  static const Color blueC500 = Color(0xFF383838);
  static const Color blueC600 = Color(0xFF2E2E2E);
  static const Color blueC700 = Color(0xFF272727);
  static const Color blueC800 = Color(0xFF181818);
  static const Color blueC900 = Color(0xFF0F0F0F);

  // Base tokens: purple
  static const Color purpleC50 = Color(0xFFAAAFFF);
  static const Color purpleC100 = Color(0xFF8288FE);
  static const Color purpleC200 = Color(0xFF5A62EB);
  static const Color purpleC300 = Color(0xFF454CD4);
  static const Color purpleC400 = Color(0xFF333ABE);
  static const Color purpleC500 = Color(0xFF292D86);
  static const Color purpleC600 = Color(0xFF1F2363);
  static const Color purpleC700 = Color(0xFF191B4A);
  static const Color purpleC800 = Color(0xFF111334);
  static const Color purpleC900 = Color(0xFF0B0D22);

  // Base tokens: ash
  static const Color ashC50 = Color(0xFF8D8D8D);
  static const Color ashC100 = Color(0xFF6B6B6B);
  static const Color ashC200 = Color(0xFF545454);
  static const Color ashC300 = Color(0xFF3C3C3C);
  static const Color ashC400 = Color(0xFF313131);
  static const Color ashC500 = Color(0xFF2C2C2C);
  static const Color ashC600 = Color(0xFF252525);
  static const Color ashC700 = Color(0xFF1E1E1E);
  static const Color ashC800 = Color(0xFF181818);
  static const Color ashC900 = Color(0xFF111111);

  // Base tokens: shade
  static const Color shadeC25 = Color(0xFF939393);
  static const Color shadeC50 = Color(0xFF7C7C7C);
  static const Color shadeC100 = Color(0xFF666666);
  static const Color shadeC200 = Color(0xFF4F4F4F);
  static const Color shadeC300 = Color(0xFF404040);
  static const Color shadeC400 = Color(0xFF343434);
  static const Color shadeC500 = Color(0xFF282828);
  static const Color shadeC600 = Color(0xFF202020);
  static const Color shadeC700 = Color(0xFF1A1A1A);
  static const Color shadeC800 = Color(0xFF151515);
  static const Color shadeC900 = Color(0xFF0E0E0E);

  // Component tokens
  static const Color themePreviewPrimary = blackC80;
  static const Color themePreviewSecondary = blackC100;
  static const Color themePreviewGhost = white;

  static const Color pillBackground = blackC100;
  static const Color pillBackgroundHover = blackC125;
  static const Color pillHighlight = blueC200;
  static const Color pillActiveBackground = shadeC700;

  static const Color globalAccentA = blueC200;
  static const Color globalAccentB = blueC300;

  static const Color lightBarLight = purpleC800;

  static const Color buttonsToggle = purpleC300;
  static const Color buttonsToggleDisabled = blackC200;
  static const Color buttonsDanger = semanticRoseC300;
  static const Color buttonsDangerHover = semanticRoseC200;
  static const Color buttonsSecondary = blackC100;
  static const Color buttonsSecondaryText = semanticSilverC300;
  static const Color buttonsSecondaryHover = blackC150;
  static const Color buttonsPrimary = white;
  static const Color buttonsPrimaryText = blackC50;
  static const Color buttonsPrimaryHover = semanticSilverC100;
  static const Color buttonsPurple = purpleC600;
  static const Color buttonsPurpleHover = purpleC400;
  static const Color buttonsCancel = blackC100;
  static const Color buttonsCancelHover = blackC150;

  static const Color backgroundMain = blackC75;
  static const Color backgroundSecondary = blackC75;
  static const Color backgroundSecondaryHover = blackC75;
  static const Color backgroundAccentA = purpleC600;
  static const Color backgroundAccentB = blackC100;

  static const Color modalBackground = shadeC800;

  static const Color typeLogo = purpleC100;
  static const Color typeEmphasis = white;
  static const Color typeText = shadeC50;
  static const Color typeDimmed = shadeC50;
  static const Color typeDivider = ashC500;
  static const Color typeSecondary = ashC100;
  static const Color typeDanger = semanticRedC100;
  static const Color typeSuccess = semanticGreenC100;
  static const Color typeLink = purpleC100;
  static const Color typeLinkHover = purpleC50;

  static const Color searchBackground = blackC100;
  static const Color searchHoverBackground = shadeC900;
  static const Color searchFocused = blackC125;
  static const Color searchPlaceholder = shadeC200;
  static const Color searchIcon = shadeC500;
  static const Color searchText = white;

  static const Color mediaCardHoverBackground = shadeC900;
  static const Color mediaCardHoverAccent = blackC250;
  static const Color mediaCardHoverShadow = blackC50;
  static const Color mediaCardShadow = shadeC800;
  static const Color mediaCardBarColor = ashC200;
  static const Color mediaCardBarFillColor = purpleC100;
  static const Color mediaCardBadge = shadeC700;
  static const Color mediaCardBadgeText = ashC100;

  static const Color largeCardBackground = blackC100;
  static const Color largeCardIcon = purpleC400;

  static const Color dropdownBackground = blackC100;
  static const Color dropdownAltBackground = blackC80;
  static const Color dropdownHoverBackground = blackC150;
  static const Color dropdownHighlight = semanticYellowC400;
  static const Color dropdownHighlightHover = semanticYellowC200;
  static const Color dropdownText = shadeC50;
  static const Color dropdownSecondary = shadeC100;
  static const Color dropdownBorder = shadeC400;
  static const Color dropdownContentBackground = blackC50;

  static const Color authenticationBorder = shadeC300;
  static const Color authenticationInputBg = blackC100;
  static const Color authenticationInputBgHover = blackC150;
  static const Color authenticationWordBackground = shadeC500;
  static const Color authenticationCopyText = shadeC100;
  static const Color authenticationCopyTextHover = ashC50;
  static const Color authenticationErrorText = semanticRoseC100;

  static const Color settingsSidebarActiveLink = blackC100;
  static const Color settingsSidebarBadge = shadeC900;
  static const Color settingsSidebarTypeSecondary = shadeC200;
  static const Color settingsSidebarTypeInactive = shadeC50;
  static const Color settingsSidebarTypeIcon = blackC200;
  static const Color settingsSidebarTypeIconActivated = purpleC200;
  static const Color settingsSidebarTypeActivated = purpleC100;

  static const Color settingsCardBorder = shadeC700;
  static const Color settingsCardBackground = blackC100;
  static const Color settingsCardAltBackground = blackC100;
  static const Color settingsSaveBarBackground = blackC50;

  static const Color utilsDivider = ashC300;

  static const Color onboardingBar = shadeC400;
  static const Color onboardingBarFilled = purpleC300;
  static const Color onboardingDivider = shadeC200;
  static const Color onboardingCard = shadeC800;
  static const Color onboardingCardHover = shadeC700;
  static const Color onboardingBorder = shadeC600;
  static const Color onboardingGood = purpleC100;
  static const Color onboardingBest = semanticYellowC100;
  static const Color onboardingLink = purpleC100;

  static const Color errorsCard = blackC75;
  static const Color errorsBorder = ashC500;
  static const Color errorsTypeSecondary = ashC100;

  static const Color aboutCircle = blackC100;
  static const Color aboutCircleText = ashC50;

  static const Color editBadgeBg = ashC500;
  static const Color editBadgeBgHover = ashC400;
  static const Color editBadgeText = ashC50;

  static const Color progressBackground = ashC50;
  static const Color progressPreloaded = ashC50;
  static const Color progressFilled = purpleC200;

  static const Color videoButtonBackground = ashC600;
  static const Color videoAutoPlayBackground = ashC800;
  static const Color videoAutoPlayHover = ashC600;

  static const Color videoScrapingCard = blackC50;
  static const Color videoScrapingError = semanticRedC200;
  static const Color videoScrapingSuccess = semanticGreenC200;
  static const Color videoScrapingLoading = purpleC200;
  static const Color videoScrapingNoresult = blackC200;

  static const Color videoAudioSet = purpleC200;

  static const Color videoContextBackground = blackC50;
  static const Color videoContextLight = shadeC50;
  static const Color videoContextBorder = ashC600;
  static const Color videoContextHoverColor = ashC600;
  static const Color videoContextButtonFocus = ashC500;
  static const Color videoContextFlagBg = ashC500;
  static const Color videoContextInputBg = blackC100;
  static const Color videoContextButtonOverInputHover = ashC500;
  static const Color videoContextInputPlaceholder = ashC200;
  static const Color videoContextCardBorder = ashC700;
  static const Color videoContextSlider = blackC200;
  static const Color videoContextSliderFilled = purpleC200;
  static const Color videoContextError = semanticRedC200;
  static const Color videoContextButtonsList = ashC700;
  static const Color videoContextButtonsActive = ashC900;
  static const Color videoContextCloseHover = ashC800;
  static const Color videoContextTypeMain = semanticSilverC300;
  static const Color videoContextTypeSecondary = ashC200;
  static const Color videoContextTypeAccent = purpleC200;
}

class AppTextStyles {
  AppTextStyles._();

  static TextTheme textTheme(TextTheme base) {
    final themed = GoogleFonts.dmSansTextTheme(base);

    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: themed.displaySmall?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        color: AppColors.typeText,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: themed.titleSmall?.copyWith(
        color: AppColors.typeText,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(color: AppColors.typeText),
      bodyMedium: themed.bodyMedium?.copyWith(color: AppColors.typeText),
      bodySmall: themed.bodySmall?.copyWith(color: AppColors.typeSecondary),
      labelLarge: themed.labelLarge?.copyWith(
        color: AppColors.typeEmphasis,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        color: AppColors.typeSecondary,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        color: AppColors.typeSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static TextStyle get link => GoogleFonts.dmSans(
    color: AppColors.typeLink,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get success => GoogleFonts.dmSans(
    color: AppColors.typeSuccess,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get danger => GoogleFonts.dmSans(
    color: AppColors.typeDanger,
    fontWeight: FontWeight.w600,
  );
}

class AppSpacing {
  AppSpacing._();

  static const double unit = 4.0;
  static const double x0 = 0.0;
  static const double x1 = unit;
  static const double x2 = unit * 2;
  static const double x3 = unit * 3;
  static const double x4 = unit * 4;
  static const double x5 = unit * 5;
  static const double x6 = unit * 6;
  static const double x8 = unit * 8;
  static const double x10 = unit * 10;
  static const double x12 = unit * 12;
  static const double x16 = unit * 16;
  static const double x20 = unit * 20;
  static const double x30 = unit * 30;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    final textTheme = AppTextStyles.textTheme(base.textTheme);
    const colorScheme = ColorScheme.dark(
      primary: AppColors.buttonsToggle,
      onPrimary: AppColors.buttonsPrimaryText,
      secondary: AppColors.globalAccentA,
      onSecondary: AppColors.typeEmphasis,
      error: AppColors.videoScrapingError,
      onError: AppColors.typeEmphasis,
      surface: AppColors.backgroundMain,
      onSurface: AppColors.typeText,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryColor: AppColors.buttonsToggle,
      scaffoldBackgroundColor: AppColors.backgroundMain,
      canvasColor: AppColors.backgroundSecondary,
      cardColor: AppColors.modalBackground,
      dividerColor: AppColors.utilsDivider,
      disabledColor: AppColors.buttonsToggleDisabled,
      focusColor: AppColors.dropdownHighlight,
      hintColor: AppColors.searchPlaceholder,
      hoverColor: AppColors.searchHoverBackground,
      highlightColor: AppColors.mediaCardHoverBackground,
      splashColor: AppColors.searchFocused,
      shadowColor: AppColors.mediaCardShadow,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.typeLink,
        selectionColor: AppColors.videoContextSliderFilled,
        selectionHandleColor: AppColors.videoContextSliderFilled,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundMain,
        foregroundColor: AppColors.typeEmphasis,
        surfaceTintColor: AppColors.backgroundMain,
        shadowColor: AppColors.mediaCardShadow,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(color: AppColors.typeEmphasis),
        actionsIconTheme: const IconThemeData(color: AppColors.typeEmphasis),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.modalBackground,
        shadowColor: AppColors.mediaCardShadow,
        surfaceTintColor: AppColors.modalBackground,
        margin: EdgeInsets.all(AppSpacing.x4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.modalBackground,
        surfaceTintColor: AppColors.modalBackground,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.modalBackground,
        surfaceTintColor: AppColors.modalBackground,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.errorsCard,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.typeEmphasis,
        ),
        actionTextColor: AppColors.typeLink,
        disabledActionTextColor: AppColors.typeSecondary,
        closeIconColor: AppColors.typeEmphasis,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.utilsDivider,
        thickness: 1,
        space: AppSpacing.x4,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.typeSecondary,
        textColor: AppColors.typeText,
        tileColor: Colors.transparent,
        selectedColor: AppColors.typeEmphasis,
        selectedTileColor: AppColors.settingsSidebarActiveLink,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.searchBackground,
        hoverColor: AppColors.searchHoverBackground,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.searchPlaceholder,
        ),
        prefixIconColor: AppColors.searchIcon,
        suffixIconColor: AppColors.searchIcon,
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.typeSecondary,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.typeLink,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          borderSide: const BorderSide(color: AppColors.authenticationBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          borderSide: const BorderSide(color: AppColors.authenticationBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          borderSide: const BorderSide(color: AppColors.typeLink),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          borderSide: const BorderSide(
            color: AppColors.authenticationErrorText,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          borderSide: const BorderSide(
            color: AppColors.authenticationErrorText,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(
            AppColors.buttonsPrimary,
          ),
          foregroundColor: const WidgetStatePropertyAll(
            AppColors.buttonsPrimaryText,
          ),
          overlayColor: const WidgetStatePropertyAll(
            AppColors.buttonsPrimaryHover,
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x3,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.x4),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(
            AppColors.buttonsSecondary,
          ),
          foregroundColor: const WidgetStatePropertyAll(
            AppColors.buttonsSecondaryText,
          ),
          overlayColor: const WidgetStatePropertyAll(
            AppColors.buttonsSecondaryHover,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.dropdownBorder),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x3,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.x4),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.typeLink),
          overlayColor: const WidgetStatePropertyAll(
            AppColors.searchHoverBackground,
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: AppSpacing.x2,
            ),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.buttonsPurple,
        foregroundColor: AppColors.typeEmphasis,
      ),
      iconTheme: const IconThemeData(color: AppColors.typeEmphasis),
      primaryIconTheme: const IconThemeData(color: AppColors.typeEmphasis),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.mediaCardBadge,
        disabledColor: AppColors.buttonsToggleDisabled,
        selectedColor: AppColors.buttonsToggle,
        secondarySelectedColor: AppColors.buttonsToggle,
        deleteIconColor: AppColors.typeEmphasis,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.typeEmphasis,
        ),
        side: const BorderSide(color: AppColors.dropdownBorder),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        indicatorColor: AppColors.buttonsToggle,
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(color: AppColors.typeSecondary),
        ),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        indicatorColor: AppColors.buttonsToggle,
        selectedIconTheme: const IconThemeData(color: AppColors.typeEmphasis),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.typeSecondary,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.typeEmphasis,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.typeEmphasis,
        unselectedLabelColor: AppColors.typeSecondary,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.buttonsToggle, width: 2),
        ),
        dividerColor: AppColors.utilsDivider,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.progressFilled,
        linearTrackColor: AppColors.progressBackground,
        circularTrackColor: AppColors.progressBackground,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.videoContextSliderFilled,
        inactiveTrackColor: AppColors.videoContextSlider,
        thumbColor: AppColors.videoContextSliderFilled,
        overlayColor: AppColors.videoContextSliderFilled.withValues(
          alpha: 0.18,
        ),
        valueIndicatorColor: AppColors.videoContextBackground,
        valueIndicatorTextStyle: textTheme.labelSmall?.copyWith(
          color: AppColors.typeEmphasis,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: const WidgetStatePropertyAll(AppColors.buttonsToggle),
        checkColor: const WidgetStatePropertyAll(AppColors.typeEmphasis),
        overlayColor: const WidgetStatePropertyAll(
          AppColors.searchHoverBackground,
        ),
        side: const BorderSide(color: AppColors.dropdownBorder),
      ),
      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(AppColors.buttonsToggle),
        overlayColor: WidgetStatePropertyAll(AppColors.searchHoverBackground),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(AppColors.typeEmphasis),
        trackColor: const WidgetStatePropertyAll(AppColors.buttonsToggle),
        trackOutlineColor: const WidgetStatePropertyAll(
          AppColors.dropdownBorder,
        ),
        overlayColor: const WidgetStatePropertyAll(
          AppColors.searchHoverBackground,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.dropdownBackground,
        surfaceTintColor: AppColors.dropdownBackground,
        textStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.videoContextBackground,
          borderRadius: BorderRadius.circular(AppSpacing.x2),
          border: Border.all(color: AppColors.videoContextBorder),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.typeEmphasis),
      ),
    );
  }
}
