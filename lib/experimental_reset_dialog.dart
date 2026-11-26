import 'package:flutter/material.dart';

import 'components.dart';
import 'theme.dart';
import 'action_feedback.dart';

const experimentalWasteResetNotice =
    '尚未在實體硬體上驗證透過本程式將非零廢墨計數器歸零。原始協定的歸零操作曾成功，程式診斷及歸零安全措施已測試。';

const wasteInkSpillWarning =
    '計數器歸零不會清空或修復廢墨吸收棉。如果吸收棉飽和、阻塞或充滿墨水，請先更換，再執行歸零或印表機的墨水沖洗（Ink Flush）。沖洗與清潔會將更多廢墨排入吸收棉。吸收棉已滿或阻塞時繼續操作可能導致墨水溢出。本程式僅重設廢墨計數器，不會執行墨水沖洗。';

class ExperimentalResetDialog extends StatefulWidget {
  final String serial;
  final double counter;
  const ExperimentalResetDialog({
    super.key,
    required this.serial,
    required this.counter,
  });

  @override
  State<ExperimentalResetDialog> createState() =>
      _ExperimentalResetDialogState();
}

class _ExperimentalResetDialogState extends State<ExperimentalResetDialog> {
  bool accepted = false;
  bool spillAccepted = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('要將此印表機的計數器歸零嗎？'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(usbServiceRequirement, style: TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            Text(
              '墨水溢出警告',
              style: TextStyle(
                color: colors(context).warning,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(wasteInkSpillWarning, style: TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            const BadgeLabel('實驗性歸零', warning: true),
            const SizedBox(height: 12),
            Text(
              experimentalWasteResetNotice,
              style: TextStyle(color: colors(context).warning, height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Canon PIXMA G7020\n${widget.serial}\n\nThe current software counter is ${widget.counter.toStringAsFixed(1)}%. One clear command will be sent after a fresh connection check.\n\nKeep USB connected and leave the printer powered on until the result appears.',
              style: const TextStyle(height: 1.7),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: spillAccepted,
              onChanged: (value) =>
                  setState(() => spillAccepted = value ?? false),
              title: const Text(
                '我了解吸收棉飽和或阻塞可能導致墨水溢出。',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: accepted,
              onChanged: (value) => setState(() => accepted = value ?? false),
              title: const Text('我了解此歸零功能屬於實驗性質。'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: accepted && spillAccepted
            ? () => Navigator.pop(context, true)
            : null,
        child: const Text('計數器歸零'),
      ),
    ],
  );
}
