import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'app_info.dart';
import 'update_controller.dart';
import 'software_updates.dart';
import 'platform/install_update.dart';
import 'components.dart';
import 'theme.dart';
import 'overview.dart';
import 'maintenance.dart';
import 'experimental_reset_dialog.dart';
import 'action_feedback.dart';
import 'queue_view.dart';
import 'diagnostics_view.dart';
import 'platform/appearance.dart';
import 'platform/save_report.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final smoke = arguments
      .where((v) => v.startsWith('--smoke-output='))
      .firstOrNull;
  final proof = arguments
      .where((v) => v.startsWith('--network-proof='))
      .firstOrNull;
  final diagnosticsProof = arguments
      .where((v) => v.startsWith('--diagnostics-proof='))
      .firstOrNull;
  final serviceProof = arguments
      .where((v) => v.startsWith('--service-proof='))
      .firstOrNull;
  final controller = CareController(
    directory:
        smoke == null &&
            proof == null &&
            diagnosticsProof == null &&
            serviceProof == null
        ? null
        : Directory.systemTemp.createTempSync('fixma-pixma-launch-'),
  );
  String? forwardingError;
  if (Platform.isWindows && const bool.fromEnvironment('dart.vm.product')) {
    try {
      if (await forwardInstalledUpdate(
        controller.directory,
        applicationVersion,
        arguments,
      )) {
        controller.dispose();
        exit(0);
      }
    } catch (_) {
      forwardingError = 'The installed update could not start. This version is still available. Use Check for updates to repair the installation.';
    }
  }
  var initialized = true;
  try {
    await controller.initialize(scan: false);
  } catch (e) {
    initialized = false;
    controller.lastError =
        'Could not open local application data. ${CareController.cleanError(e)}';
  }
  runApp(
    FixmaPixma(
      controller: controller,
      initialPage: serviceProof != null
          ? 3
          : diagnosticsProof != null
          ? 6
          : 0,
    ),
  );
  if (!initialized) return;
  if (forwardingError != null) {
    controller.message = forwardingError;
    controller.notifyListeners();
  }
  if (arguments.any((v) => v.startsWith('--update-ready='))) {
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 5),
      );
      await acknowledgeUpdateStartup(controller.directory, arguments);
    } catch (_) {
      /* The updater retains the previous version if startup is not confirmed. */
    }
  }
  if (serviceProof != null) {
    // Explicit hardware diagnostic mode. A zero-counter reset is checked only
    // through the controller guard; no nonzero reset is ever invoked here.
    await controller.diagnose();
    final r = controller.report;
    final output = serviceProof.substring('--service-proof='.length);
    String? blocked;
    if (r != null && r.waste == 0 && controller.liveValid) {
      controller.setServiced(true);
      await controller.reset();
      blocked = controller.lastError;
    }
    final forbidden = controller.history.any(
      (h) => h['counterClearAttempted'] == true,
    );
    await File('$output.txt')
        .writeAsString(controller.exportText(), flush: true);
    await File(output).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': applicationVersion,
        'nativeLaunch': true,
        'report': r?.toJson(),
        'diagnosticCompleted': r != null && controller.liveValid && !r.sample,
        'historySaved': controller.history.any(
          (h) => h['kind'] == 'diagnostic' && h['status'] == 'Completed',
        ),
        'zeroCounterResetBlocked': blocked?.contains('already at zero') == true,
        'resetBlockReason': blocked,
        'counterClearAttempted': forbidden,
        'error': r == null ? controller.lastError : null,
        'isolatedDirectory': controller.directory.path,
      }),
      flush: true,
    );
    controller.dispose();
    exit(0);
  }
  await controller.discover();
  controller.startMonitoring();
  if (diagnosticsProof != null) {
    await controller.checkConnections();
    final output = diagnosticsProof.substring('--diagnostics-proof='.length);
    await File(output).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': applicationVersion,
        'nativeLaunch': true,
        'error': controller.lastError,
        'checks': controller.connectionChecks.map((v) => v.toJson()).toList(),
        'identity': controller.diagnosticIdentity?.toJson(),
        'usage': controller.canonUsage?.toJson(),
        'networkState': controller.networkStatus?.stateLabel,
        'usbInterfaces': controller.devices
            .map(
              (d) => {
                'service': d['service'],
                'product': d['path'].toString().contains('pid_12fe')
                    ? 'service'
                    : 'normal or unknown',
              },
            )
            .toList(),
        'printingStarted': false,
        'maintenanceStarted': false,
        'resetsSent': 0,
      }),
      flush: true,
    );
    await File('$output.public.json')
        .writeAsString(controller.diagnosticSummary(), flush: true);
    controller.dispose();
    exit(0);
  }
  if (proof != null) {
    final first = controller.networkStatus?.toJson();
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (controller.successfulNetworkReads < 2 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await controller.saveNetworkSnapshot();
    final restored = CareController(directory: controller.directory);
    await restored.initialize(scan: false);
    await restored.refreshNetwork();
    final proofPath = proof.substring('--network-proof='.length);
    await File('$proofPath.txt')
        .writeAsString(controller.exportText(), flush: true);
    await File(proofPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'freshInstall': true,
        'discovery': controller.networkPrinters.map((p) => p.toJson()).toList(),
        'firstReading': first,
        'automaticRefreshReads': controller.successfulNetworkReads,
        'latestReading': controller.networkStatus?.toJson(),
        'snapshotSaved': controller.history.any(
          (h) => h['kind'] == 'network snapshot',
        ),
        'restoredSelection': restored.selectedPrinter?.toJson(),
        'restoredOnline': restored.networkOnline,
        'restoredFirmware': restored.networkStatus?.firmware,
        'error': controller.networkError,
        'counterCommandsSent': 0,
        'printJobsSubmitted': 0,
      }),
      flush: true,
    );
    restored.dispose();
    if (smoke == null) {
      controller.dispose();
      exit(0);
    }
  }
  if (smoke != null) {
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await File(smoke.substring('--smoke-output='.length)).writeAsString(
      jsonEncode({
        'launched': true,
        'version': applicationVersion,
        'theme': controller.themeMode.name,
        'usbInterfaces': controller.devices.length,
        'serviceInterfaces': controller.devices
            .where((d) => d['service'] == true)
            .length,
        'error': controller.lastError,
        'counterCommandsSent': false,
        'usbError': controller.usbError,
        'discoveredPrinters': controller.networkPrinters
            .map((p) => p.toJson())
            .toList(),
        'networkStatus': controller.networkStatus?.toJson(),
        'networkError': controller.networkError,
      }),
      flush: true,
    );
    controller.dispose();
    exit(0);
  }
}

class FixmaPixma extends StatefulWidget {
  final CareController controller;
  final bool nativeFrame;
  final UpdateController? updates;
  final int initialPage;
  const FixmaPixma({
    super.key,
    required this.controller,
    this.nativeFrame = true,
    this.updates,
    this.initialPage = 0,
  });
  @override
  State<FixmaPixma> createState() => _FixmaPixmaState();
}

class _FixmaPixmaState extends State<FixmaPixma> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  late final UpdateController updates;
  late final bool ownsUpdates;
  int page = 0;
  int diagnosticTab = 0;
  late final TextEditingController ipInput;
  CareController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    page = widget.initialPage;
    ownsUpdates = widget.updates == null;
    updates =
        widget.updates ??
        UpdateController(
          directory: c.directory,
          printerIdle: () => !c.busy && !c.disposed,
          installHandler: (prepared) async {
            final lock = c.reserveSoftwareUpdate();
            try {
              await NativeUpdateInstaller(c.directory)
                  .handoff(prepared, applicationVersion, () async {
                    await c.stop();
                    c.dispose();
                    exit(0);
                  });
            } finally {
              if (!c.disposed) c.releaseSoftwareUpdate(lock);
            }
          },
        );
    updates.addListener(updatesChanged);
    ipInput = TextEditingController(text: c.ip);
    WidgetsBinding.instance.addObserver(this);
    c.addListener(changed);
    updates.initialize();
    if (updates.installFailure) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && navigatorKey.currentContext != null) {
          showSoftwareUpdates(
            navigatorKey.currentContext!,
            updates,
            check: false,
          );
        }
      });
    }
  }

  void updatesChanged() {
    if (mounted) setState(() {});
  }

  void changed() {
    updates.printerStateChanged();
    if (mounted) {
      if (ipInput.text.isEmpty && c.ip.isNotEmpty) ipInput.text = c.ip;
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(updates.checkIfDue());
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    updates.removeListener(updatesChanged);
    if (ownsUpdates) updates.dispose();
    ipInput.dispose();
    c.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark =
        c.themeMode == ThemeMode.dark ||
        (c.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    if (widget.nativeFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setWindowsDarkFrame(dark);
      });
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Fixma Pixma',
      debugShowCheckedModeBanner: false,
      theme: careTheme(Brightness.light),
      darkTheme: careTheme(Brightness.dark),
      themeMode: c.themeMode,
      home: Builder(
        builder: (context) => Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  header(context),
                  navigation(context),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1220),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (updates.showNotice)
                                UpdateNotice(updates: updates),
                              if (c.busy) busyPanel(context),
                              if (c.message.isNotEmpty ||
                                  c.lastError.isNotEmpty)
                                notice(context),
                              if (page == 0)
                                PrinterOverview(
                                  controller: c,
                                  openService: () => setState(() => page = 3),
                                ),
                              if (page == 3) overview(context),
                              if (page == 1) maintenance(context),
                              if (page == 2) history(context),
                              if (page == 4) QueueView(controller: c),
                              if (page == 6)
                                DiagnosticsView(
                                  key: ValueKey(diagnosticTab),
                                  controller: c,
                                  initialTab: diagnosticTab,
                                  serviceGuide: () => instructions(context),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: colors(context).rail,
                      border: Border(
                        top: BorderSide(color: colors(context).line),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.usb, size: 14, color: colors(context).muted),
                        const SizedBox(width: 7),
                        Text(
                          c.busy
                              ? '處理中…'
                              : c.networkOnline
                              ? '已連線・區域網路'
                              : 'USB 與區域網路',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors(context).muted,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Version $applicationVersion',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors(context).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget navigation(BuildContext context) {
    final p = colors(context);
    return Container(
      height: 43,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, label, icon) in [
              (0, '總覽', Icons.print_outlined),
              (4, '列印佇列', Icons.list_alt_outlined),
              (3, '維修報告', Icons.description_outlined),
              (1, '維護', Icons.build_outlined),
              (2, '歷史紀錄', Icons.history),
              (6, '診斷', Icons.monitor_heart_outlined),
            ])
              Semantics(
                button: true,
                selected: page == i,
                child: InkWell(
                  onTap: () => setState(() => page = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: page == i ? p.accent : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 17,
                          color: page == i ? p.accent : p.muted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: page == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: page == i ? p.ink : p.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget header(BuildContext context) {
    final p = colors(context);
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.print_outlined, size: 22, color: p.accent),
          const SizedBox(width: 10),
          const Text(
            'Fixma Pixma',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          if (MediaQuery.sizeOf(context).width >= 1100) ...[
            const SizedBox(width: 18),
            Container(width: 1, height: 20, color: p.line),
            const SizedBox(width: 18),
            Text(
              '印表機診斷',
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
          ],
          const Spacer(),
          if (c.report != null || c.networkStatus != null)
            TextButton.icon(
              onPressed: c.busy ? null : () => export(context),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('匯出報告'),
            ),
          const SizedBox(width: 12),
          Container(height: 28, width: 1, color: p.line),
          const SizedBox(width: 12),
          IconButton(
            tooltip: '檢查更新',
            onPressed: () => showSoftwareUpdates(context, updates),
            icon: Badge(
              isLabelVisible: updates.available != null,
              child: const Icon(Icons.system_update_alt, size: 20),
            ),
          ),
          PopupMenuButton<ThemeMode>(
            tooltip: '外觀',
            initialValue: c.themeMode,
            onSelected: c.setTheme,
            itemBuilder: (_) => [
              for (final (mode, label, icon) in [
                (
                  ThemeMode.system,
                  '跟隨系統',
                  Icons.brightness_auto_outlined,
                ),
                (ThemeMode.light, '淺色', Icons.light_mode_outlined),
                (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
              ])
                PopupMenuItem(
                  value: mode,
                  child: Row(
                    children: [
                      Icon(icon, size: 18),
                      const SizedBox(width: 12),
                      Text(label),
                      const SizedBox(width: 20),
                      if (c.themeMode == mode)
                        const Icon(Icons.check, size: 17),
                    ],
                  ),
                ),
            ],
            child: Semantics(
              button: true,
              label: 'Appearance: ${c.themeMode.name}',
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      switch (c.themeMode) {
                        ThemeMode.system => Icons.brightness_auto_outlined,
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                      },
                      size: 20,
                      color: p.ink,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.keyboard_arrow_down, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget busyPanel(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Panel(
      child: Row(
        children: [
          SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors(context).accent,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              c.progress.isEmpty ? '正在尋找印表機…' : c.progress,
            ),
          ),
          TextButton(
            onPressed: c.activePeer == null ? null : c.stop,
            child: const Text('停止等待'),
          ),
        ],
      ),
    ),
  );
  Widget notice(BuildContext context) {
    final p = colors(context), error = c.lastError.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: error ? p.warning.withValues(alpha: .08) : p.tint,
          border: Border.all(
            color: error ? p.warning.withValues(alpha: .35) : p.line,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.info_outline : Icons.check_circle_outline,
              color: error ? p.warning : p.accent,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error ? c.lastError : c.message,
                style: const TextStyle(height: 1.6, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget pageTitle(BuildContext context, String title, String description) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: -.2,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colors(context).muted,
              ),
            ),
          ],
        ),
      );
  Widget overview(BuildContext context) {
    final p = colors(context), r = c.report;
    final service = c.devices.any((d) => d['service'] == true);
    final state = r?.sample == true
        ? '範例報告'
        : service
        ? '已偵測到維修模式'
        : c.devices.isNotEmpty
        ? '已偵測到一般模式'
        : '等待 USB 連線';
    final device = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('裝置資訊'),
          const SizedBox(height: 16),
          for (final (label, value) in [
            (
              '機型',
              r != null
                  ? 'Canon G7000 series${r.sample ? ' · sample' : ''}'
                  : c.networkStatus?.model ?? '尚未識別',
            ),
            (
              '維修系列',
              r != null ? 'G7000 series' : '執行診斷以識別',
            ),
            ('韌體', r?.firmware ?? '尚未讀取'),
            ('序號', r?.serial ?? '尚未讀取'),
            (
              '連線',
              r?.sample == true
                  ? '範例資料'
                  : service
                  ? 'USB／維修模式'
                  : c.devices.isNotEmpty
                  ? 'USB／一般模式'
                  : '尚未連線',
            ),
          ]) ...[
            Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
            const SizedBox(height: 3),
            SelectableText(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 17),
          ],
          Divider(height: 1, color: p.line),
          const SizedBox(height: 13),
          TextButton.icon(
            onPressed: () => instructions(context),
            icon: const Icon(Icons.help_outline, size: 16),
            label: const Text('維修模式指南'),
          ),
        ],
      ),
    );
    final report = r == null
        ? Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('維修報告'),
                const SizedBox(height: 22),
                const Text(
                  '尚無診斷報告',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '將印表機切換至維修模式並連接 USB 線，再執行診斷以讀取廢墨計數器與使用紀錄。',
                  style: TextStyle(fontSize: 14, height: 1.6, color: p.muted),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.sample,
                  icon: const Icon(Icons.description_outlined, size: 17),
                  label: const Text('開啟範例報告'),
                ),
              ],
            ),
          )
        : Panel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 13, 12, 13),
                  child: Row(
                    children: [
                      const Expanded(child: SectionLabel('維修報告')),
                      Text(
                        'Captured ${date(r.capturedAt)}',
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => rawReport(context),
                        child: const Text('查看完整報告'),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: p.tint.withValues(alpha: .6),
                    border: Border(
                      top: BorderSide(color: p.line),
                      bottom: BorderSide(color: p.line),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '廢墨計數器',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${r.waste?.toStringAsFixed(1) ?? ' - '}%',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: r.waste == null
                            ? 0
                            : (r.waste! / 100).clamp(0, 1),
                        minHeight: 4,
                        color: p.accent,
                        backgroundColor: p.line,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '韌體估算的廢墨吸收棉使用量，並非實際墨水測量值。',
                        style: TextStyle(fontSize: 12.5, color: p.muted),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('使用紀錄'),
                      const SizedBox(height: 8),
                      detail(context, '列印頁數', number(r.pages)),
                      detail(context, '影印紀錄', number(r.copies)),
                      detail(
                        context,
                        '前方紙匣進紙頁數',
                        number(r.frontPages),
                      ),
                      detail(
                        context,
                        '後方進紙頁數',
                        number(r.rearPages),
                      ),
                      detail(
                        context,
                        '計數器歸零紀錄',
                        r.resetCount?.toString() ?? ' - ',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('已儲存的錯誤紀錄'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final code in r.errorCodes.toSet())
                            BadgeLabel(code, warning: code == '5B00'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '維修後可能仍保留歷史紀錄，並不代表目前的印表機狀態。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageTitle(
          context,
          'G7020 維修診斷',
          '讀取 G7000 USB 維修資訊。網路狀態請見總覽。',
        ),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Canon PIXMA G7020',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    BadgeLabel(state, warning: r?.sample == true),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.busy ? null : () => findServicePrinter(context),
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('尋找印表機'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: c.busy ? null : () => diagnosePrinter(context),
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('執行診斷'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth < 720
              ? Column(children: [report, const SizedBox(height: 20), device])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 236, child: device),
                    const SizedBox(width: 20),
                    Expanded(child: report),
                  ],
                ),
        ),
      ],
    );
  }

  Widget detail(BuildContext context, String label, String value) {
    final p = colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.line.withValues(alpha: .65)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget maintenanceSection(
    BuildContext context,
    String title,
    String note,
    Widget content,
  ) {
    final p = colors(context);
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Padding(
              padding: const EdgeInsets.only(right: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    note,
                    style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget maintenance(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageTitle(
          context,
          '印表機維護',
          '檢查列印品質、清潔噴頭及調整 Canon 設定。',
        ),
        CanonMaintenancePanel(controller: c),
        const SizedBox(height: 24),
        Panel(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: ExpansionTile(
              title: const Text(
                '廢墨吸收棉',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '實驗性歸零・需要 USB 與維修模式・不支援 Wi-Fi 歸零',
                style: TextStyle(fontSize: 13),
              ),
              childrenPadding: const EdgeInsets.all(20),
              children: [wasteMaintenance(context)],
            ),
          ),
        ),
      ],
    );
  }

  Widget wasteMaintenance(BuildContext context) {
    final p = colors(context), r = c.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageTitle(
          context,
          '廢墨計數器歸零',
          '需要 USB 並手動進入維修模式。不支援透過 Wi-Fi 將廢墨計數器歸零。',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BadgeLabel('實驗性歸零', warning: true),
              const SizedBox(height: 10),
              Text(
                experimentalWasteResetNotice,
                style: TextStyle(color: p.warning, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              maintenanceSection(
                context,
                '1. 讀取印表機',
                '需要維修模式下的 USB 連線。',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '重新執行診斷，確認機型、韌體與目前計數值。',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: c.busy
                              ? null
                              : () => diagnosePrinter(context),
                          icon: const Icon(Icons.manage_search, size: 18),
                          label: const Text('執行診斷'),
                        ),
                        TextButton(
                          onPressed: () => instructions(context),
                          child: const Text('進入維修模式'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: p.line),
              maintenanceSection(
                context,
                '2. 計數器歸零',
                '計數器是軟體估算的吸收棉使用量。',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '廢墨吸收棉',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 14),
                        if (r != null)
                          BadgeLabel(
                            '${r.waste?.toStringAsFixed(1) ?? ' - '}%${r.sample ? ' · sample' : ''}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      wasteInkSpillWarning,
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: c.serviced,
                      onChanged: c.busy || r == null || r.sample
                          ? null
                          : (v) => c.setServiced(v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        '廢墨吸收棉已完成維護。',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: c.busy || c.resetBlocked != null
                          ? null
                          : () => confirmReset(context),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('廢墨計數器歸零'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      c.resetBlocked ?? '已準備好執行一次歸零。傳送指令前會先記錄此次操作。',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: p.line),
              maintenanceSection(
                context,
                '3. 重新開機後驗證',
                '請在印表機上完成此步驟。',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '確認歸零指令已獲回應後，使用電源鍵關機，再正常開機。確認螢幕無錯誤並嘗試一般列印。',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: ipInput,
                            onChanged: (v) => c.ip = v,
                            decoration: const InputDecoration(
                              labelText: '印表機 IP 位址（選填）',
                              hintText: '192.168.1.50',
                              prefixIcon: Icon(Icons.lan_outlined, size: 18),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: c.busy
                              ? null
                              : () => printerAction(
                                  context,
                                  title: '無法檢查印表機狀態',
                                  action: () => c.verify(ipInput.text),
                                  error: () => c.lastError,
                                  help: networkRequirement,
                                ),
                          child: const Text('檢查狀態'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget history(BuildContext context) {
    final p = colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageTitle(
          context,
          '維修歷史',
          '診斷及歸零操作紀錄儲存在此電腦。',
        ),
        if (c.repairs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                diagnosticTab = 1;
                page = 6;
              }),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(
                'Repair follow-ups · ${c.repairs.where((r) => !r.verified).length} pending',
              ),
            ),
          ),
        Panel(
          child: c.history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 44),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.history_rounded, size: 36, color: p.accent),
                        const SizedBox(height: 18),
                        const Text(
                          '尚無儲存的報告',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '執行診斷以儲存第一份報告。',
                          style: TextStyle(color: p.muted),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final entry in c.history)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        leading: Icon(
                          entry['kind'] == 'reset'
                              ? Icons.restart_alt
                              : Icons.description_outlined,
                          color: p.accent,
                        ),
                        title: Text(
                          entry['kind'] == 'reset'
                              ? '計數器歸零'
                              : entry['kind'] == 'diagnostic'
                              ? '診斷報告'
                              : entry['kind'] == 'ink refill reset'
                              ? '補墨計數器重設'
                              : entry['kind'] == 'network snapshot'
                              ? '印表機狀態快照'
                              : entry['kind'] == 'connection checks'
                              ? '連線檢查'
                              : entry['kind'] == 'repair verification'
                              ? '維修驗證'
                              : entry['kind'] == 'restart check'
                              ? '重新開機狀態檢查'
                              : entry['kind'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            date(DateTime.parse(entry['started'] as String)),
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ),
                        trailing: BadgeLabel(
                          entry['status'] as String,
                          warning: entry['status'] == 'Stopped',
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('維修紀錄'),
                            content: SizedBox(
                              width: 600,
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  '${entry['kind']} · ${entry['status']}\n\n${entry['error'] ?? 'Operation completed.'}\n${entry['beforeCounter'] != null ? 'Before: ${entry['beforeCounter']}%\nAfter: ${entry['afterCounter'] ?? 'Unverified'}%' : ''}${entry['kind'] == 'ink refill reset' ? '\nSelected: ${(entry['selectedColors'] as List?)?.join(', ') ?? 'Not recorded'}\nBefore: ${(entry['before'] as Map?)?['levels'] ?? '尚未讀取'}\nAfter: ${(entry['after'] as Map?)?['levels'] ?? 'Not verified'}\nReadback verified: ${entry['verified'] == true ? 'Yes' : 'No'}' : ''}\n\n${entry['network'] != null ? const JsonEncoder.withIndent('  ').convert(entry['network']) : (entry['report'] as Map?)?['raw'] ?? 'The detailed exchange is retained in the local history file.'}',
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('關閉'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Text(
          'Stored in ${c.directory.path}',
          style: TextStyle(fontSize: 12, height: 1.6, color: p.muted),
        ),
      ],
    );
  }

  Future<void> export(BuildContext context) async {
    try {
      final path = saveReportPath();
      if (path != null) {
        await File(path).writeAsString(c.exportText(), flush: true);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('維修報告已儲存。')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(CareController.cleanError(e))));
      }
    }
  }

  Future<void> confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ExperimentalResetDialog(
        serial: c.report!.serial,
        counter: c.report!.waste!,
      ),
    );
    if (confirmed == true && context.mounted) {
      await printerAction(
        context,
        title: '廢墨計數器歸零未完成',
        action: c.reset,
        error: () => c.lastError,
        help: usbServiceRequirement,
        mayHaveSentCommand: true,
      );
    }
  }

  Future<void> diagnosePrinter(BuildContext context) async {
    await printerAction(
      context,
      title: 'USB 維修診斷失敗',
      action: c.diagnose,
      error: () => c.lastError,
      help: usbServiceRequirement,
    );
  }

  Future<void> findServicePrinter(BuildContext context) async {
    await printerAction(
      context,
      title: '找不到 USB 維修模式印表機',
      action: c.discover,
      error: () => c.usbError.isNotEmpty
          ? c.usbError
          : c.devices.any((device) => device['service'] == true)
          ? ''
          : c.devices.isEmpty
          ? 'No USB printer was found.'
          : 'A USB printer was found, but its service-mode interface is not available.',
      help: usbServiceRequirement,
    );
  }

  Future<void> instructions(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('進入維修模式'),
      scrollable: true,
      content: const SizedBox(
        width: 440,
        child: Text(
          '已驗證的 PIXMA G7020 操作程序：\n\n1. 連接 USB 資料線。使用電源鍵關機，等待關機完成且電源燈熄滅。保持電源線連接。\n2. 按住電源鍵。\n3. 按住電源鍵時，按下並放開 Stop 鍵六次。\n4. 放開電源鍵。等待機構停止且綠色電源燈恆亮。LCD 應為空白或黑色。\n5. 尋找維修模式印表機並執行診斷，確認 USB 維修連線。僅電源燈恆亮不能證明已進入維修模式。\n\n此程序已在 G7020 韌體 1.050 測試，請勿假設其他機型適用。操作完成後使用電源鍵關機，等待關機完成再正常開機。診斷透過 USB 讀取報告，不會要求列印。',
          style: TextStyle(height: 1.8),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('完成'),
        ),
      ],
    ),
  );
  Future<void> rawReport(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        c.report!.sample ? 'Sample service report' : '維修報告',
      ),
      content: SizedBox(
        width: 660,
        height: 420,
        child: SingleChildScrollView(
          child: SelectableText(
            c.report!.raw,
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('關閉'),
        ),
      ],
    ),
  );
}
