import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pstream_android/models/app_update_info.dart';
import 'package:pstream_android/services/app_update_service.dart';

enum AppUpdatePhase {
  idle,
  checking,
  available,
  upToDate,
  downloading,
  installing,
  error,
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.installedVersionName,
    this.installedVersionCode,
    this.available,
    this.downloadProgress = 0,
    this.errorMessage,
  });

  final AppUpdatePhase phase;
  final String? installedVersionName;
  final int? installedVersionCode;
  final AppUpdateInfo? available;
  final double downloadProgress;
  final String? errorMessage;

  bool get hasUpdate =>
      available != null && phase == AppUpdatePhase.available;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    String? installedVersionName,
    int? installedVersionCode,
    AppUpdateInfo? available,
    bool clearAvailable = false,
    double? downloadProgress,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      installedVersionName: installedVersionName ?? this.installedVersionName,
      installedVersionCode: installedVersionCode ?? this.installedVersionCode,
      available: clearAvailable ? null : (available ?? this.available),
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final appUpdateServiceProvider = Provider<AppUpdateService>((Ref ref) {
  final AppUpdateService service = AppUpdateService();
  ref.onDispose(service.dispose);
  return service;
});

final installedPackageInfoProvider = FutureProvider<PackageInfo>((Ref ref) {
  return ref.watch(appUpdateServiceProvider).installedPackageInfo();
});

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((Ref ref) {
  return AppUpdateController(ref.watch(appUpdateServiceProvider));
});

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(this._service) : super(const AppUpdateState());

  final AppUpdateService _service;

  Future<void> loadInstalledVersion() async {
    try {
      final PackageInfo info = await _service.installedPackageInfo();
      state = state.copyWith(
        installedVersionName: info.version,
        installedVersionCode: int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (_) {
      // Non-fatal; Settings still works without the label.
    }
  }

  /// Quiet launch check (respects 24h throttle + dismissed version).
  Future<void> checkOnLaunch() async {
    await loadInstalledVersion();
    await checkForUpdate(force: false, quiet: true);
  }

  Future<void> checkForUpdate({
    bool force = true,
    bool quiet = false,
  }) async {
    if (state.phase == AppUpdatePhase.checking ||
        state.phase == AppUpdatePhase.downloading ||
        state.phase == AppUpdatePhase.installing) {
      return;
    }

    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      clearError: true,
    );

    try {
      await loadInstalledVersion();
      final AppUpdateInfo? update = await _service.checkForUpdate(force: force);
      if (update == null) {
        state = state.copyWith(
          phase: quiet ? AppUpdatePhase.idle : AppUpdatePhase.upToDate,
          clearAvailable: true,
        );
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.available,
        available: update,
      );
    } catch (error) {
      if (quiet) {
        state = state.copyWith(
          phase: AppUpdatePhase.idle,
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> downloadAndInstall() async {
    final AppUpdateInfo? update = state.available;
    if (update == null) {
      return;
    }

    state = state.copyWith(
      phase: AppUpdatePhase.downloading,
      downloadProgress: 0,
      clearError: true,
    );

    try {
      await _service.downloadAndInstall(
        update,
        onProgress: (double progress) {
          state = state.copyWith(
            phase: AppUpdatePhase.downloading,
            downloadProgress: progress,
          );
        },
      );
      state = state.copyWith(
        phase: AppUpdatePhase.installing,
        downloadProgress: 1,
      );
    } catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.error,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> dismissAvailableUpdate() async {
    final AppUpdateInfo? update = state.available;
    if (update != null) {
      await _service.dismissUpdate(update);
    }
    state = state.copyWith(
      phase: AppUpdatePhase.idle,
      clearAvailable: true,
      clearError: true,
    );
  }
}
