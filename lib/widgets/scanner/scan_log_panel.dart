import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

enum ScanLogSeverity { info, warning, error }

enum ScanLogFilter { all, warnError, errorOnly }

class ScanLogEntry {
  final String message;
  final ScanLogSeverity severity;

  const ScanLogEntry({required this.message, required this.severity});
}

List<ScanLogEntry> filterScanLogs(List<ScanLogEntry> logs, ScanLogFilter filter) {
  switch (filter) {
    case ScanLogFilter.warnError:
      return logs
          .where((e) => e.severity == ScanLogSeverity.warning || e.severity == ScanLogSeverity.error)
          .toList(growable: false);
    case ScanLogFilter.errorOnly:
      return logs.where((e) => e.severity == ScanLogSeverity.error).toList(growable: false);
    case ScanLogFilter.all:
      return logs;
  }
}

Color scanLogSeverityColor(ScanLogSeverity severity) {
  switch (severity) {
    case ScanLogSeverity.info:
      return AppColors.cyan;
    case ScanLogSeverity.warning:
      return AppColors.amber;
    case ScanLogSeverity.error:
      return AppColors.red;
  }
}

class ScanLogPanel extends StatelessWidget {
  final List<ScanLogEntry> logs;
  final ScanLogFilter logFilter;
  final bool logPanelCollapsed;
  final bool logAutoScroll;
  final ScrollController logScrollController;
  final bool compact;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<ScanLogFilter> onSetFilter;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onClearLogs;

  const ScanLogPanel({
    super.key,
    required this.logs,
    required this.logFilter,
    required this.logPanelCollapsed,
    required this.logAutoScroll,
    required this.logScrollController,
    required this.compact,
    required this.onToggleCollapsed,
    required this.onSetFilter,
    required this.onToggleAutoScroll,
    required this.onClearLogs,
  });

  @override
  Widget build(BuildContext context) {
    final filteredLogs = filterScanLogs(logs, logFilter);
    final collapsed = compact ? true : logPanelCollapsed;
    final height = collapsed ? (compact ? 40.0 : 52.0) : (compact ? 100.0 : 140.0);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onToggleCollapsed,
                child: Icon(
                  logPanelCollapsed ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LOGS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              _LogFilterChip(
                label: 'All',
                active: logFilter == ScanLogFilter.all,
                onTap: () => onSetFilter(ScanLogFilter.all),
              ),
              const SizedBox(width: 6),
              _LogFilterChip(
                label: 'Warn+Error',
                active: logFilter == ScanLogFilter.warnError,
                onTap: () => onSetFilter(ScanLogFilter.warnError),
              ),
              const SizedBox(width: 6),
              _LogFilterChip(
                label: 'Error',
                active: logFilter == ScanLogFilter.errorOnly,
                onTap: () => onSetFilter(ScanLogFilter.errorOnly),
              ),
              const SizedBox(width: 6),
              _LogFilterChip(
                label: logAutoScroll ? 'AutoScroll On' : 'AutoScroll Off',
                active: logAutoScroll,
                onTap: onToggleAutoScroll,
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClearLogs,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${filteredLogs.length}/${logs.length}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            Expanded(
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Text(
                        'No logs for selected filter',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      controller: logScrollController,
                      itemCount: filteredLogs.length,
                      itemBuilder: (_, i) {
                        final entry = filteredLogs[i];
                        final baseColor = scanLogSeverityColor(entry.severity);
                        final isLatest = i == filteredLogs.length - 1;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            entry.message,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: isLatest ? baseColor : baseColor.withValues(alpha: 0.58),
                              fontSize: 11,
                              fontWeight: isLatest ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LogFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan.withValues(alpha: 0.2) : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.cyan : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
