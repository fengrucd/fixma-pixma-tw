import 'package:flutter/material.dart';

import 'components.dart';
import 'controller.dart';
import 'core/canon_maintenance.dart';
import 'theme.dart';
import 'action_feedback.dart';

class CanonMaintenancePanel extends StatelessWidget {
  final CareController controller;
  const CanonMaintenancePanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, p = colors(context), check = controller.canonControls;
    final valid = check != null && check.target.key == c.selectedPrinter?.key;
    final enabled = valid && c.canReadCanonControls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valid ? check.identity.model : 'Canon 印表機控制',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      valid
                          ? 'Firmware ${check.identity.firmware} · ${check.identity.serial}'
                          : 'Wi-Fi or Ethernet · Normal mode · No USB required. Read printer controls to begin.',
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    if (!c.networkOnline)
                      Text(
                        '請在總覽選擇已連線的印表機。',
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              OutlinedButton.icon(
                onPressed: c.canReadCanonControls
                    ? () => printerAction(
                        context,
                        title: '無法讀取印表機控制資訊',
                        action: c.loadCanonControls,
                        error: () => c.lastError,
                        help: networkRequirement,
                      )
                    : null,
                icon: const Icon(Icons.refresh, size: 17),
                label: Text(
                  valid ? '重新讀取控制資訊' : '讀取印表機控制資訊',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _taskRow(
                context,
                CanonTask.nozzleCheck,
                '列印一張紙以檢查黑色網格與彩色條紋。',
                '列印噴嘴檢查圖',
                enabled,
              ),
              Divider(height: 1, color: p.line),
              _taskRow(
                context,
                CanonTask.cleaning,
                '對所有顏色執行標準清潔。會消耗墨水，僅在必要時執行。',
                '清潔噴頭',
                enabled,
              ),
              Divider(height: 1, color: p.line),
              _taskRow(
                context,
                CanonTask.alignmentCheck,
                '列印一張目前校正值的檢查圖。',
                '列印校正檢查圖',
                enabled,
              ),
              Divider(height: 1, color: p.line),
              _taskRow(
                context,
                CanonTask.automaticAlignment,
                '列印兩張紙並讓印表機自動校正，約需 4 至 5 分鐘。',
                '噴頭校正',
                enabled,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'After cleaning, print a nozzle check and examine the sheet. Gaps in the black grid or missing color bands can indicate clogged nozzles.',
          style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        const SectionLabel('印表機設定'),
        const SizedBox(height: 10),
        if (!valid)
          Panel(
            child: Text(
              'Read printer controls to view quiet mode, power settings, paper clearance, and drying wait.',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
            ),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final key in CanonSettings.allowed.keys) ...[
                  if (key != CanonSettings.allowed.keys.first)
                    Divider(height: 1, color: p.line),
                  _CanonSettingRow(
                    key: ValueKey('${check.checkedAt}-$key'),
                    controller: c,
                    name: key,
                    value: valid ? check.settings.values[key] ?? '' : '',
                    enabled: enabled,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _taskRow(
    BuildContext context,
    CanonTask task,
    String note,
    String button,
    bool enabled,
  ) {
    final p = colors(context), check = controller.canonControls;
    final supported =
        check?.capabilities.supports(task, letterPaper) == true ||
        check?.capabilities.supports(task, a4Paper) == true;
    final action = OutlinedButton(
      onPressed: enabled && supported ? () => _confirm(context, task) : null,
      child: Text(button),
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, box) {
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                note,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
              ),
            ],
          );
          return box.maxWidth < 620
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description, const SizedBox(height: 12), action],
                )
              : Row(
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 24),
                    SizedBox(width: 190, child: action),
                  ],
                );
        },
      ),
    );
  }

  Future<void> _confirm(BuildContext context, CanonTask task) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TaskDialog(task: task),
    );
    if (result != null && context.mounted) {
      await printerAction(
        context,
        title: '${task.label} did not complete',
        action: () =>
            controller.runCanonTask(task, prepared: true, paper: result),
        error: () => controller.lastError,
        help: networkRequirement,
        mayHaveSentCommand: true,
      );
    }
  }
}

class _TaskDialog extends StatefulWidget {
  final CanonTask task;
  const _TaskDialog({required this.task});
  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  String paper = letterPaper;
  bool ready = false;
  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return AlertDialog(
      title: Text(task.label),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task == CanonTask.automaticAlignment
                    ? 'Load two sheets of plain Letter or A4 paper in the front cassette and open the output tray. The printer will print and read its alignment patterns, then save the adjustment automatically. Allow about 4 to 5 minutes. Leave the printer powered on and do not use it until this finishes.'
                    : task.usesPaper
                    ? 'Load one sheet of plain Letter or A4 paper in the front cassette. Open the output tray. The printer will print its own check pattern.'
                    : 'This runs one standard cleaning cycle for all colors. Leave the printer powered on until it finishes. Cleaning uses ink.',
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              if (task.usesPaper) ...[
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: paper,
                  decoration: const InputDecoration(
                    labelText: '紙匣內的紙張',
                  ),
                  items: const [
                    DropdownMenuItem(value: letterPaper, child: Text('Letter')),
                    DropdownMenuItem(value: a4Paper, child: Text('A4')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => paper = v);
                  },
                ),
              ],
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: ready,
                onChanged: (v) => setState(() => ready = v ?? false),
                title: Text(
                  task == CanonTask.automaticAlignment
                      ? 'Two sheets are loaded, the output tray is open, and the tanks contain enough ink.'
                      : task.usesPaper
                      ? 'The paper and output tray are ready.'
                      : 'I checked that the tanks contain enough ink.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: ready ? () => Navigator.pop(context, paper) : null,
          child: Text(
            task == CanonTask.automaticAlignment
                ? '開始校正'
                : task.usesPaper
                ? '列印檢查圖'
                : '開始清潔',
          ),
        ),
      ],
    );
  }
}

class _CanonSettingRow extends StatefulWidget {
  final CareController controller;
  final String name, value;
  final bool enabled;
  const _CanonSettingRow({
    super.key,
    required this.controller,
    required this.name,
    required this.value,
    required this.enabled,
  });
  @override
  State<_CanonSettingRow> createState() => _CanonSettingRowState();
}

class _CanonSettingRowState extends State<_CanonSettingRow> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final p = colors(context),
        key = widget.name,
        allowed = CanonSettings.allowed[key]!;
    selected ??= widget.value;
    final notes = {
      'quiet': '降低運作噪音，列印速度可能變慢。',
      'autoPowerOn': '收到列印工作時喚醒印表機。',
      'autoPowerOff':
          '閒置後自動關機，使用傳真時可能保持開機。',
      'paperGap': '紙張摩擦或出現墨漬時，增加噴頭間隙。',
      'dryLevel': '增加頁面間的墨水乾燥時間。',
    };
    final editor = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            hint: Text(
              CanonSettings.display(key, widget.value),
              style: const TextStyle(fontSize: 13),
            ),
            decoration: InputDecoration(
              isDense: true,
              labelText: CanonSettings.labels[key],
            ),
            items: [
              if (!allowed.contains(widget.value))
                DropdownMenuItem(
                  value: widget.value,
                  enabled: false,
                  child: Text(
                    CanonSettings.display(key, widget.value),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              for (final value in allowed)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    CanonSettings.display(key, value),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: widget.enabled
                ? (v) => setState(() => selected = v)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed:
              widget.enabled &&
                  allowed.contains(selected) &&
                  selected != widget.value
              ? () => printerAction(
                  context,
                  title: '無法儲存印表機設定',
                  action: () =>
                      widget.controller.saveCanonSetting(key, selected!),
                  error: () => widget.controller.lastError,
                  help: networkRequirement,
                  mayHaveSentCommand: true,
                )
              : null,
          child: const Text('套用'),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, box) {
          final description = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                CanonSettings.labels[key]!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                notes[key]!,
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
              ),
              if (widget.value.isNotEmpty)
                Text(
                  'Current: ${CanonSettings.display(key, widget.value)}',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.8),
                ),
            ],
          );
          return box.maxWidth < 670
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description, const SizedBox(height: 14), editor],
                )
              : Row(
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 24),
                    editor,
                  ],
                );
        },
      ),
    );
  }
}
