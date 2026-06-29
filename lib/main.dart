import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/pixrompt_controller.dart';
import 'app/pixrompt_sync_controller.dart';
import 'data/hive_pixrompt_repository.dart';
import 'data/sync_state_repository.dart';
import 'ui/pixrompt_app.dart';
import 'ui/system_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await applyPixromptSystemUi();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    applyPixromptSystemUi();
  });
  await Hive.initFlutter('pixrompt');
  final repository = await HivePixromptRepository.open();
  final controller = PixromptController(repository);
  await controller.initialize();
  final syncStateRepository = await HiveSyncStateRepository.open();
  final syncController = PixromptSyncController(
    pixromptController: controller,
    syncStateRepository: syncStateRepository,
  );
  unawaited(syncController.refreshStatus());
  runApp(
    PixromptApp(
      controller: controller,
      syncController: syncController,
    ),
  );
}
