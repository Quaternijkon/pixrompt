import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import 'pixrompt_design.dart';

class PromptFilterPage extends StatelessWidget {
  const PromptFilterPage({super.key, required this.controller});

  final PixromptController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('prompt.filterPage'),
      backgroundColor: PixromptPalette.darkBackground,
      appBar: AppBar(
        title: const Text('Prompt 列表'),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final prompts = controller.state.prompts;
          if (prompts.isEmpty) {
            return const Center(child: Text('暂无 Prompt'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: prompts.length + 1,
            separatorBuilder: (context, index) =>
                const SizedBox(height: PixromptSpace.sm),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PixromptRadius.md),
                  ),
                  tileColor: PixromptPalette.darkSurface,
                  leading: const Icon(Icons.clear_all),
                  title: const Text('全部 Prompt'),
                  onTap: () {
                    controller.updateSearchFilters(
                      controller.state.searchFilters.copyWith(prompt: null),
                    );
                    Navigator.of(context).pop();
                  },
                );
              }
              final prompt = prompts[index - 1];
              final count = controller.state.allImages
                  .where((image) => image.prompt == prompt)
                  .length;
              return ListTile(
                key: ValueKey('prompt.filter.$prompt'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PixromptRadius.md),
                ),
                tileColor: PixromptPalette.darkSurface,
                selectedTileColor: PixromptPalette.darkSurfaceHigh,
                leading: const Icon(Icons.notes_outlined),
                title: Text(
                  prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('$count'),
                selected: controller.state.searchFilters.prompt == prompt,
                onTap: () {
                  controller.updateSearchFilters(
                    controller.state.searchFilters.copyWith(prompt: prompt),
                  );
                  Navigator.of(context).pop();
                },
              );
            },
          );
        },
      ),
    );
  }
}
