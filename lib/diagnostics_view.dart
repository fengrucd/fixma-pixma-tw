import 'dart:convert';

import 'package:flutter/material.dart';

import 'components.dart';
import 'controller.dart';
import 'core/model_support.dart';
import 'core/report.dart';
import 'core/report_comparison.dart';
import 'core/repair_record.dart';
import 'core/capture_inspector.dart';
import 'platform/save_diagnostic.dart';
import 'problem_report.dart';
import 'theme.dart';

class DiagnosticsView extends StatefulWidget {
  final CareController controller;
  final int initialTab;
  final VoidCallback? serviceGuide;
  const DiagnosticsView({
    super.key,
    required this.controller,
    this.initialTab = 0,
    this.serviceGuide,
  });
  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView> {
  CareController get c => widget.controller;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
  }

  String baseline = '', comparison = '';
  String counter(double? value) =>
      value == null ? 'Not recorded' : '${value.toStringAsFixed(1)}%';
  String keyOf(ServiceReport r) =>
      '${r.serial}/${r.capturedAt.toIso8601String()}/${r.sample}';
  @override
  Widget build(BuildContext context) {
    final p = colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '診斷',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 16),
            ReportProblemButton(saveReport: () => saveDiagnosticSummary(c)),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Understand the connection, follow a repair, and compare saved evidence.',
          style: TextStyle(color: p.muted, height: 1.6),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 6,
          runSpacing: 8,
          children: [
            for (final (i, label) in [
              '連線',
              '維修追蹤',
              '比較報告',
              '機型支援',
            ].indexed)
              ChoiceChip(
                label: Text(label),
                selected: tab == i,
                onSelected: (_) => setState(() => tab = i),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (tab == 0) connection(context),
        if (tab == 1) repairs(context),
        if (tab == 2) reports(context),
        if (tab == 3) profiles(context),
      ],
    );
  }

  Widget connection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('連線檢查'),
            const SizedBox(height: 8),
            const Text(
              '讀取 USB 介面、網路狀態及可見的列印佇列。不會執行列印、清潔或歸零。',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: c.busy || c.networkRefreshing
                      ? null
                      : c.checkConnections,
                  icon: const Icon(Icons.manage_search, size: 18),
                  label: const Text('執行連線檢查'),
                ),
                OutlinedButton(
                  onPressed: c.busy ? null : c.rememberUsbBaseline,
                  child: const Text('儲存 USB 基準資料'),
                ),
                TextButton(
                  onPressed: widget.serviceGuide,
                  child: const Text('G7020 維修模式指南'),
                ),
                TextButton(
                  onPressed: c.connectionChecks.isEmpty || c.busy
                      ? null
                      : () => exportSummary(context),
                  child: const Text('匯出診斷摘要'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'The summary includes model, firmware, advertised capabilities, connection errors and recent operation outcomes. Known identifiers are redacted. Review the JSON before sharing. Nothing is uploaded automatically.',
              style: TextStyle(color: colors(context).muted, height: 1.5),
            ),
            if (c.usbBaseline != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Baseline: ${c.usbBaseline!.length} Canon interface(s). Kept for this app session.',
                  style: TextStyle(color: colors(context).muted),
                ),
              ),
            if (c.connectionCheckedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Last checked ${date(c.connectionCheckedAt!)}',
                  style: TextStyle(color: colors(context).muted),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (c.connectionChecks.isNotEmpty)
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, check) in c.connectionChecks.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        check.attention
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                        size: 19,
                        color: check.attention
                            ? colors(context).warning
                            : colors(context).accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${check.area} · ${check.status}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              check.detail,
                              style: TextStyle(
                                height: 1.5,
                                color: colors(context).muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      if (c.devices.isNotEmpty) ...[
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('已偵測到的 Canon USB 介面'),
              const SizedBox(height: 10),
              for (final d in c.devices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    '04A9:${ModelSupport.usbProduct(d['path'] as String)}  ·  ${d['service'] == true ? 'Shared service identity; model not yet verified' : 'Normal or unverified USB identity'}',
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: c.busy || c.diagnosticIdentity == null
                ? null
                : c.trackDeviceIssue,
            child: const Text('追蹤目前印表機問題'),
          ),
          TextButton(
            onPressed: () => inspect(context),
            child: const Text('離線檢查擷取的回應'),
          ),
        ],
      ),
    ],
  );

  Widget repairs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Follow-ups are saved on this computer. Status checks only read the selected printer; they never repeat a reset.',
        style: TextStyle(color: colors(context).muted, height: 1.6),
      ),
      const SizedBox(height: 16),
      if (c.repairLoadError.isNotEmpty) Text(c.repairLoadError),
      if (c.repairs.isEmpty)
        const Panel(
          child: Text(
            'No repair follow-ups yet. An attempted waste-counter reset creates one automatically. You can also track an issue after running connection checks.',
          ),
        ),
      for (final r in c.repairs)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: repair(context, r),
        ),
    ],
  );

  Widget repair(BuildContext context, RepairRecord r) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              r.kind == 'deviceIssue'
                  ? '印表機問題追蹤'
                  : '廢墨計數器維修',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            BadgeLabel(r.stage, warning: !r.verified),
          ],
        ),
        const SizedBox(height: 10),
        SelectableText('${r.model} · ${r.serial} · firmware ${r.firmware}'),
        const SizedBox(height: 5),
        Text(
          'Started ${date(r.createdAt)}',
          style: TextStyle(color: colors(context).muted, fontSize: 12),
        ),
        if (r.kind == 'wasteCounter')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Before: ${counter(r.beforeCounter)}  ·  Readback: ${counter(r.afterCounter)}\nCommand acknowledged: ${r.acknowledged ? 'Yes' : 'Unknown - do not repeat'}',
            ),
          ),
        const SizedBox(height: 14),
        Text(r.observation, style: const TextStyle(height: 1.6)),
        if (r.checkedAt != null)
          Text(
            'Status observed ${date(r.checkedAt!)}',
            style: TextStyle(fontSize: 12, color: colors(context).muted),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: c.busy ? null : () => confirmRestart(context, r),
              child: Text(
                r.restartConfirmed
                    ? '確認再次重新開機'
                    : '我已使用電源鍵重新開機',
              ),
            ),
            FilledButton(
              onPressed:
                  c.busy ||
                      c.networkRefreshing ||
                      !r.restartConfirmed ||
                      c.selectedPrinter == null
                  ? null
                  : () => c.checkRepair(r),
              child: const Text('讀取重新開機後的狀態'),
            ),
          ],
        ),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              '我已確認印表機螢幕無錯誤',
              style: TextStyle(fontSize: 14),
            ),
            value: r.displayClear,
            onChanged: c.busy || !r.restartConfirmed
                ? null
                : (v) => c.confirmRepairDisplay(r, v == true),
          ),
        ),
        if (r.verified)
          Text(
            'Normal status and display confirmed. Printed quality still requires its own test.',
            style: TextStyle(color: colors(context).muted, height: 1.5),
          ),
      ],
    ),
  );

  Future<void> confirmRestart(BuildContext context, RepairRecord r) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認正常重新開機'),
        content: const Text(
          'Confirm that you turned this printer off with its Power button, waited for shutdown to finish, then turned it on normally. This records your confirmation; it does not restart the printer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新開機已完成'),
          ),
        ],
      ),
    );
    if (answer == true) c.confirmRepairRestart(r);
  }

  Widget reports(BuildContext context) {
    final all = c.comparisonReports, keys = all.map(keyOf).toSet();
    final a = keys.contains(baseline) ? baseline : '',
        b = keys.contains(comparison) ? comparison : '';
    ReportComparison? result;
    String error = '';
    if (a.isNotEmpty && b.isNotEmpty) {
      try {
        result = ReportComparison(
          all.firstWhere((r) => keyOf(r) == a),
          all.firstWhere((r) => keyOf(r) == b),
        );
      } catch (e) {
        error = CareController.cleanError(e);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('比較維修報告'),
              const SizedBox(height: 8),
              const Text(
                'Choose two reports from the same printer. Changes describe reported values; stored error history does not mean a fault is currently active.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, size) {
                  final fields = [
                    reportPicker(
                      '基準',
                      a,
                      all,
                      (v) => setState(() => baseline = v),
                    ),
                    reportPicker(
                      '比較對象',
                      b,
                      all,
                      (v) => setState(() => comparison = v),
                    ),
                  ];
                  return size.maxWidth < 650
                      ? Column(
                          children: [
                            fields[0],
                            const SizedBox(height: 12),
                            fields[1],
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: fields[0]),
                            const SizedBox(width: 18),
                            Expanded(child: fields[1]),
                          ],
                        );
                },
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: c.busy ? null : () => importDialog(context),
                icon: const Icon(Icons.input, size: 17),
                label: const Text('匯入已儲存的報告文字或 JSON'),
              ),
              Text(
                '${all.length} report(s) available. Imports are kept locally for comparison and cannot enable reset.',
                style: TextStyle(color: colors(context).muted, height: 1.5),
              ),
            ],
          ),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error,
              style: TextStyle(color: colors(context).warning),
            ),
          ),
        if (result != null) ...[
          const SizedBox(height: 16),
          Panel(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final label in [
                    '回報欄位',
                    '基準',
                    '比較值',
                    '變化',
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (final (label, before, after, delta) in result.rows)
                    DataRow(
                      cells: [
                        DataCell(Text(label)),
                        DataCell(Text(before)),
                        DataCell(Text(after)),
                        DataCell(Text(delta)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '廢墨估算值降低並不能證明吸收棉已實際維護。',
            style: TextStyle(color: colors(context).muted),
          ),
        ],
      ],
    );
  }

  Widget reportPicker(
    String label,
    String selected,
    List<ServiceReport> all,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label/$selected/${all.length}'),
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: [
      const DropdownMenuItem(value: '', child: Text('選擇報告')),
      for (final r in all)
        DropdownMenuItem(
          value: keyOf(r),
          child: Text(
            '${date(r.capturedAt)} · ${r.serial}${r.sample ? ' · sample / unverified import' : ''}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) => onChanged(v ?? ''),
  );

  Future<void> importDialog(BuildContext context) async {
    final input = TextEditingController();
    String error = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('匯入比較報告'),
          content: SizedBox(
            width: 650,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste a raw G7000 report or saved history JSON. Raw text has no trusted date and is treated as unverified sample data.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 2 * 1024 * 1024,
                  decoration: const InputDecoration(
                    labelText: '報告文字或 JSON',
                    counterText: '',
                  ),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error,
                      style: TextStyle(color: colors(ctx).warning),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  c.addComparisonReports(input.text);
                  Navigator.pop(ctx);
                } catch (e) {
                  update(() => error = CareController.cleanError(e));
                }
              },
              child: const Text('匯入以供比較'),
            ),
          ],
        ),
      ),
    );
    // Let the dialog's closing transition release the text field first.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
  }

  Widget profiles(BuildContext context) => Column(
    children: [
      const Panel(
        child: Text(hardwareValidationNotice, style: TextStyle(height: 1.6)),
      ),
      const SizedBox(height: 16),
      for (final profile in ModelSupport.profiles)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      profile.label,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    BadgeLabel(
                      profile.verified
                          ? '已驗證裝置設定檔'
                          : '研究候選機型',
                      warning: !profile.verified,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Reference firmware ${profile.firmware} · ${profile.note}',
                  style: TextStyle(color: colors(context).muted, height: 1.6),
                ),
                const SizedBox(height: 14),
                for (final (feature, status) in profile.features)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: LayoutBuilder(
                      builder: (context, size) => size.maxWidth < 550
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feature,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(status),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: Text(feature)),
                                Expanded(
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: colors(context).muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const Panel(
        child: Text(
          'Other IPP printers may expose standard network status and queues. Their advertised capabilities do not authorize Canon service commands. Additional absorber groups, EEPROM backup, firmware flashing, and unvalidated model resets are not enabled.',
          style: TextStyle(height: 1.6),
        ),
      ),
    ],
  );

  Future<void> exportSummary(BuildContext context) async {
    try {
      final path = await saveDiagnosticSummary(c);
      if (path == null) return;
      c.message = 'Diagnostic summary saved. Review it before sharing.';
      c.notifyListeners();
    } catch (e) {
      c.lastError = CareController.cleanError(e);
      c.notifyListeners();
    }
  }

  Future<void> inspect(BuildContext context) async {
    final input = TextEditingController();
    String result = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('離線檢查擷取的回應'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Decode received G7000 service frames using a captured session keyword. This tool never connects to a printer or sends commands. Keep private printer data local.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: input,
                    minLines: 5,
                    maxLines: 9,
                    maxLength: 256 * 1024,
                    decoration: const InputDecoration(
                      labelText: '擷取資料 JSON',
                      hintText: '{"keyword":"010203","opcode":21,"frames":["40 hex digits"]}',
                      counterText: '',
                    ),
                  ),
                  if (result.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SelectableText(
                        result,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('關閉'),
            ),
            FilledButton(
              onPressed: () {
                update(() {
                  try {
                    result = const JsonEncoder.withIndent('  ')
                        .convert(inspectCapture(input.text, c.profile));
                  } catch (e) {
                    result = CareController.cleanError(e);
                  }
                });
              },
              child: const Text('離線解碼'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
  }
}
