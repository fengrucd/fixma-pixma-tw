import 'package:flutter/material.dart';

import 'components.dart';
import 'controller.dart';
import 'core/print_queue.dart';
import 'theme.dart';
import 'action_feedback.dart';

class QueueView extends StatelessWidget {
  final CareController controller;
  const QueueView({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, p = colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '列印佇列',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ),
            OutlinedButton.icon(
              onPressed: c.busy || c.networkRefreshing
                  ? null
                  : () => printerAction(
                      context,
                      title: '無法讀取列印佇列',
                      action: c.refreshQueues,
                      error: () => [
                        c.lastError,
                        if (c.selectedPrinter != null) c.printerQueueError,
                        c.windowsQueueError,
                      ].where((text) => text.isNotEmpty).join('\n\n'),
                      help: 'Printer-side jobs require a selected network printer in normal mode. Windows queues are read from this PC; check the installed queue and Windows Print Spooler if that source failed.',
                    ),
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('更新佇列'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'See jobs received by the printer and jobs waiting on this PC. Jobs still held on other devices are visible only on those devices.',
          style: TextStyle(color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (c.networkOnline &&
            c
                    .networkStatus
                    ?.attributes['printer-is-accepting-jobs']
                    ?.firstOrNull ==
                false) ...[
          Panel(
            child: Text(
              'The printer is not accepting new jobs. An empty queue does not clear a busy operation or a panel prompt; check the printer display if it stays busy.',
              style: TextStyle(color: p.warning, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
        ],
        const Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SectionLabel('印表機端'),
            BadgeLabel('實驗性取消功能', warning: true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Queue listing is verified. Canceling a job already processing inside the printer has not been verified on hardware.',
          style: TextStyle(color: p.warning, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 10),
        _snapshot(
          context,
          c.printerJobs,
          c.printerQueueError,
          'Read the printer queue to see jobs it has received.',
        ),
        const SizedBox(height: 24),
        const SectionLabel('此 Windows 電腦'),
        const SizedBox(height: 10),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'windows-${c.selectedQueue?.identity}-${c.localQueues.length}',
                ),
                initialValue: c.selectedQueue?.identity ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Windows 印表機佇列',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('選擇 Windows 佇列'),
                  ),
                  for (final q in c.localQueues)
                    DropdownMenuItem(
                      value: q.identity,
                      child: Text(q.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: c.busy || c.networkRefreshing
                    ? null
                    : (value) => printerAction(
                        context,
                        title: '無法讀取 Windows 佇列',
                        action: () => c.chooseQueue(
                          c.localQueues
                              .where((q) => q.identity == value)
                              .firstOrNull,
                        ),
                        error: () => c.windowsQueueError,
                        help: 'Check that this queue is installed on this PC and that Windows Print Spooler is running. Queues on other PCs or phones are not visible here.',
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                c.selectedQueue == null
                    ? 'Refresh queues, then choose the exact queue. USB and network installations can have separate jobs.'
                    : '${c.selectedQueue!.driver}\nPort: ${c.selectedQueue!.port}',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (c.selectedQueue != null || c.windowsQueueError.isNotEmpty)
          _snapshot(
            context,
            c.windowsJobs,
            c.windowsQueueError,
            'Choose a Windows queue to read its jobs.',
          ),
        const SizedBox(height: 16),
        Text(
          'Cancellation cannot recall pages already printed. Access to another user’s jobs depends on the printer or Windows permissions.',
          style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _snapshot(
    BuildContext context,
    QueueSnapshot? snapshot,
    String error,
    String placeholder,
  ) {
    final p = colors(context), c = controller;
    if (error.isNotEmpty) {
      return Panel(
        child: Text(error, style: TextStyle(color: p.warning, height: 1.5)),
      );
    }
    if (snapshot == null) {
      return Panel(
        child: Text(placeholder, style: TextStyle(color: p.muted)),
      );
    }
    final eligible = snapshot.cancelable;
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snapshot.label.isEmpty
                            ? '印表機佇列'
                            : snapshot.label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${snapshot.jobs.length} job${snapshot.jobs.length == 1 ? '' : 's'} · Read ${date(snapshot.readAt)}',
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (eligible.isNotEmpty)
                  OutlinedButton(
                    onPressed: c.busy || c.networkRefreshing
                        ? null
                        : () => _confirm(context, snapshot, eligible),
                    child: const Text('取消列出的工作'),
                  ),
              ],
            ),
          ),
          if (snapshot.jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
              child: Text(
                '未回報等待中的列印工作。',
                style: TextStyle(color: p.muted),
              ),
            ),
          for (final job in snapshot.jobs) ...[
            Divider(height: 1, color: p.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: p.muted, size: 21),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title.isEmpty ? '未命名工作' : job.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Job ${job.id} · ${job.owner.isEmpty ? 'Owner unavailable' : job.owner} · ${job.state}${job.pages != null && job.pages! > 0 ? ' · ${job.printed ?? 0}/${job.pages} impressions' : ''}',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  TextButton(
                    onPressed:
                        !c.busy &&
                            !c.networkRefreshing &&
                            eligible.any(
                              (j) => j.fingerprint == job.fingerprint,
                            )
                        ? () => _confirm(context, snapshot, [job])
                        : null,
                    child: const Text('取消工作'),
                  ),
                ],
              ),
            ),
          ],
          if (snapshot.truncated)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Showing the first 200 jobs. Canceling this list leaves other jobs untouched.',
              ),
            ),
          if (snapshot.jobs.isNotEmpty && !snapshot.cancelSupported)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'This printer does not provide supported cancellation with a verifiable identity.',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    QueueSnapshot snapshot,
    List<QueueJob> jobs,
  ) async {
    final experimental = !snapshot.sourceKey.startsWith('windows:');
    var acceptedExperimental = false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            jobs.length == 1
                ? '取消此工作？'
                : 'Cancel ${jobs.length} listed jobs?',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (experimental) ...[
                    const BadgeLabel(
                      '實驗性取消功能',
                      warning: true,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '尚未在實體硬體驗證取消印表機內部正在處理的工作。取消可能失敗或需要時間生效。',
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    snapshot.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  for (final j in jobs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${j.id} · ${j.title}'),
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    '僅會要求取消這些工作，已列印的頁面無法收回。',
                  ),
                  if (experimental)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: acceptedExperimental,
                      onChanged: (value) =>
                          setState(() => acceptedExperimental = value ?? false),
                      title: const Text(
                        '我了解印表機端取消功能屬於實驗性質。',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留工作'),
            ),
            FilledButton(
              onPressed: !experimental || acceptedExperimental
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('取消工作'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && context.mounted) {
      await printerAction(
        context,
        title: '佇列取消操作未完成',
        action: () => controller.cancelJobs(snapshot, jobs, confirmed: true),
        error: () => controller.lastError,
        help: 'Refresh the same queue and check which jobs are still listed. Check its network connection or Windows spooler before making another selection.',
        mayHaveSentCommand: true,
      );
    }
  }
}
