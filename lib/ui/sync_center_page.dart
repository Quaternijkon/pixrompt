import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../app/pixrompt_sync_controller.dart';
import '../domain/prompt_image.dart';
import '../domain/sync_models.dart';
import 'pixrompt_design.dart';
import 'stored_image.dart';
import 'system_ui.dart';

Future<void> showSyncCenterPage(
  BuildContext context, {
  required PixromptController controller,
  required PixromptSyncController syncController,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SyncCenterPage(
        controller: controller,
        syncController: syncController,
      ),
    ),
  );
}

class SyncCenterPage extends StatelessWidget {
  const SyncCenterPage({
    super.key,
    required this.controller,
    required this.syncController,
  });

  final PixromptController controller;
  final PixromptSyncController syncController;

  @override
  Widget build(BuildContext context) {
    return PixromptEdgeToEdge(
      child: Scaffold(
        key: const ValueKey('syncCenter.page'),
        backgroundColor: PixromptPalette.darkBackground,
        appBar: AppBar(
          title: const Text('同步中心'),
          actions: [
            AnimatedBuilder(
              animation: syncController,
              builder: (context, _) {
                final syncing = syncController.status.isSyncing;
                return IconButton(
                  key: const ValueKey('syncCenter.manualSyncAction'),
                  tooltip: syncing ? '正在同步' : '立即同步',
                  onPressed: syncing ? null : _manualSync,
                  icon: syncing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                );
              },
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([controller, syncController]),
          builder: (context, _) {
            final images = controller.state.allImages;
            final status = syncController.status;
            final synced = images.where(_isImageSynced).length;
            final pending = images.length - synced;
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                PixromptSpace.lg,
                PixromptSpace.md,
                PixromptSpace.lg,
                PixromptSpace.xl,
              ),
              children: [
                _SyncSummaryBand(
                  total: images.length,
                  synced: synced,
                  pending: pending,
                  pendingDeletions: status.pendingDeletionCount,
                  status: status,
                ),
                const SizedBox(height: PixromptSpace.lg),
                _ProgressPanel(progress: status.progress),
                const SizedBox(height: PixromptSpace.lg),
                _QueuePanel(progress: status.progress),
                const SizedBox(height: PixromptSpace.lg),
                _ImageSyncList(images: images, controller: controller),
              ],
            );
          },
        ),
      ),
    );
  }

  void _manualSync() {
    syncController.manualSync().catchError((_) {
      // The controller publishes the failure through SyncStatus.
    });
  }
}

class _SyncSummaryBand extends StatelessWidget {
  const _SyncSummaryBand({
    required this.total,
    required this.synced,
    required this.pending,
    required this.pendingDeletions,
    required this.status,
  });

  final int total;
  final int synced;
  final int pending;
  final int pendingDeletions;
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: pixromptSurfaceDecoration(
        color: PixromptPalette.darkSurfaceHigh.withOpacity(0.58),
        radius: PixromptRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(PixromptSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.isSyncing
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_done_outlined,
                  color: Colors.white,
                ),
                const SizedBox(width: PixromptSpace.sm),
                Expanded(
                  child: Text(
                    status.accountEmail?.isNotEmpty ?? false
                        ? status.accountEmail!
                        : '未登录',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PixromptSpace.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth =
                    constraints.hasBoundedWidth ? constraints.maxWidth : 560.0;
                final columnCount = maxWidth >= 560 ? 4 : 2;
                final metricWidth = ((maxWidth -
                            PixromptSpace.sm * (columnCount - 1)) /
                        columnCount)
                    .clamp(0.0, double.infinity)
                    .toDouble();
                return Wrap(
                  spacing: PixromptSpace.sm,
                  runSpacing: PixromptSpace.sm,
                  children: [
                    SizedBox(
                      key: const ValueKey('syncCenter.metric.total'),
                      width: metricWidth,
                      child: _SummaryMetric(
                        label: '全部',
                        value: '$total',
                        icon: Icons.photo_library_outlined,
                      ),
                    ),
                    SizedBox(
                      key: const ValueKey('syncCenter.metric.synced'),
                      width: metricWidth,
                      child: _SummaryMetric(
                        label: '已同步',
                        value: '$synced',
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                    SizedBox(
                      key: const ValueKey('syncCenter.metric.pending'),
                      width: metricWidth,
                      child: _SummaryMetric(
                        label: '待同步',
                        value: '$pending',
                        icon: Icons.cloud_upload_outlined,
                      ),
                    ),
                    SizedBox(
                      key: const ValueKey(
                        'syncCenter.metric.pendingDeletions',
                      ),
                      width: metricWidth,
                      child: _SummaryMetric(
                        label: '待删除',
                        value: '$pendingDeletions',
                        icon: Icons.delete_outline,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: PixromptSpace.md),
            Text(
              status.message?.isNotEmpty ?? false
                  ? status.message!
                  : _lastSyncLabel(status.lastSyncAt),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(PixromptRadius.md),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(PixromptSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(height: PixromptSpace.sm),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: PixromptSpace.xs),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    return _Section(
      title: '同步进度',
      icon: Icons.stacked_line_chart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: '同步进度',
            value: _progressSemanticsValue(progress),
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                key: const ValueKey('syncCenter.progressBar'),
                value: progress.isActive ? fraction : fraction ?? 0,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: PixromptSpace.md),
          Wrap(
            spacing: PixromptSpace.sm,
            runSpacing: PixromptSpace.sm,
            children: [
              _InfoPill(
                icon: Icons.route_outlined,
                text: progress.phase.isEmpty ? '空闲' : progress.phase,
              ),
              _InfoPill(
                icon: Icons.playlist_add_check,
                text: '${progress.completedItems}/${progress.totalItems}',
              ),
              _InfoPill(
                icon: Icons.speed,
                text: _formatSpeed(progress.bytesPerSecond),
              ),
              _InfoPill(
                icon: Icons.data_usage,
                text:
                    '${_formatBytes(progress.bytesDone)} / ${_formatBytes(progress.bytesTotal)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final queue = progress.queue;
    return _Section(
      title: '同步列表',
      icon: Icons.list_alt,
      child: queue.isEmpty
          ? const _EmptyPanel(label: '当前没有传输任务')
          : Column(
              key: const ValueKey('syncCenter.queueList'),
              children: [
                for (final item in queue)
                  _QueueRow(
                    key: ValueKey('syncCenter.queue.${item.id}'),
                    item: item,
                  ),
              ],
            ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.item});

  final SyncQueueItem item;

  @override
  Widget build(BuildContext context) {
    final fraction = item.fraction;
    return Padding(
      padding: const EdgeInsets.only(bottom: PixromptSpace.sm),
      child: Row(
        children: [
          Icon(_queueIcon(item), size: 22, color: _queueColor(item)),
          const SizedBox(width: PixromptSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: PixromptSpace.xs),
                Text(
                  item.detail ?? _queueStateLabel(item.state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PixromptSpace.xs),
                LinearProgressIndicator(
                  value: fraction,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),
          const SizedBox(width: PixromptSpace.md),
          Text(
            _queueStateLabel(item.state),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _ImageSyncList extends StatelessWidget {
  const _ImageSyncList({
    required this.images,
    required this.controller,
  });

  final List<PromptImageItem> images;
  final PixromptController controller;

  @override
  Widget build(BuildContext context) {
    final sorted = images.toList(growable: false)
      ..sort((a, b) {
        final state = _syncWeight(a).compareTo(_syncWeight(b));
        if (state != 0) return state;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return _Section(
      title: '图片同步情况',
      icon: Icons.image_search,
      child: sorted.isEmpty
          ? const _EmptyPanel(label: '暂无图片')
          : Column(
              key: const ValueKey('syncCenter.imageList'),
              children: [
                for (final image in sorted)
                  _ImageSyncRow(
                    key: ValueKey('syncCenter.image.${image.uid}'),
                    image: image,
                    controller: controller,
                  ),
              ],
            ),
    );
  }
}

class _ImageSyncRow extends StatelessWidget {
  const _ImageSyncRow({
    super.key,
    required this.image,
    required this.controller,
  });

  final PromptImageItem image;
  final PixromptController controller;

  @override
  Widget build(BuildContext context) {
    final synced = _isImageSynced(image);
    return Padding(
      padding: const EdgeInsets.only(bottom: PixromptSpace.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(PixromptRadius.sm),
            child: SizedBox.square(
              dimension: 56,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoredImage(
                    loader: controller.imageBytes(image.imageKey),
                    fit: BoxFit.cover,
                    backgroundColor: Colors.black,
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        synced
                            ? Icons.check_circle
                            : Icons.cloud_upload_outlined,
                        key: ValueKey('syncCenter.imageStatus.${image.uid}'),
                        size: 18,
                        color: synced
                            ? const Color(0xFF7DD3A7)
                            : const Color(0xFFFBBF24),
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: PixromptSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  image.prompt.trim().isEmpty ? image.uid : image.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: PixromptSpace.xs),
                Text(
                  'ID ${image.uid}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: PixromptSpace.xs),
                Text(
                  synced ? _lastSyncLabel(image.lastSyncedAt) : '待同步',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: PixromptSpace.sm),
          _StateChip(synced: synced),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.synced});

  final bool synced;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: synced
            ? const Color(0xFF134E4A).withOpacity(0.62)
            : const Color(0xFF78350F).withOpacity(0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: synced
              ? const Color(0xFF5EEAD4).withOpacity(0.42)
              : const Color(0xFFFCD34D).withOpacity(0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          synced ? '已同步' : '待同步',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: pixromptSurfaceDecoration(
        color: PixromptPalette.darkSurface.withOpacity(0.72),
        radius: PixromptRadius.lg,
        elevated: false,
      ),
      child: Padding(
        padding: const EdgeInsets.all(PixromptSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: PixromptSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PixromptSpace.lg),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PixromptSpace.md,
          vertical: PixromptSpace.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: PixromptSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Center(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

bool _isImageSynced(PromptImageItem image) {
  return image.lastSyncedAt != null;
}

int _syncWeight(PromptImageItem image) {
  return _isImageSynced(image) ? 1 : 0;
}

IconData _queueIcon(SyncQueueItem item) {
  switch (item.kind) {
    case syncQueueKindUpload:
      return Icons.cloud_upload_outlined;
    case syncQueueKindDownload:
      return Icons.cloud_download_outlined;
    case syncQueueKindPush:
      return Icons.upload_file_outlined;
    case syncQueueKindPull:
      return Icons.downloading_outlined;
    case syncQueueKindDelete:
      return Icons.delete_outline;
    default:
      return Icons.sync;
  }
}

Color _queueColor(SyncQueueItem item) {
  switch (item.state) {
    case syncQueueStateComplete:
      return const Color(0xFF7DD3A7);
    case syncQueueStateFailed:
      return PixromptPalette.danger;
    case syncQueueStateActive:
      return PixromptPalette.accent;
    default:
      return Colors.white70;
  }
}

String _queueStateLabel(String state) {
  switch (state) {
    case syncQueueStateActive:
      return '进行中';
    case syncQueueStateComplete:
      return '完成';
    case syncQueueStateFailed:
      return '失败';
    default:
      return '等待';
  }
}

String _lastSyncLabel(int? value) {
  if (value == null) return '尚未同步';
  final time = DateTime.fromMillisecondsSinceEpoch(value);
  String two(int number) => number.toString().padLeft(2, '0');
  return '上次同步：${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

String _progressSemanticsValue(SyncProgress progress) {
  final phase = progress.phase.isEmpty ? '空闲' : progress.phase;
  return '$phase，${progress.completedItems}/${progress.totalItems}，'
      '${_formatBytes(progress.bytesDone)} / ${_formatBytes(progress.bytesTotal)}';
}

String _formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  return '${_formatBytes(bytesPerSecond.round())}/s';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
  if (bytes >= kb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
