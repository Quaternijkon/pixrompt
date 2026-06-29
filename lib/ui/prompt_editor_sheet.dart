import 'package:flutter/material.dart';

import 'pixrompt_design.dart';

class PromptEditorDraft {
  const PromptEditorDraft({required this.prompt});

  final String prompt;
}

Future<PromptEditorDraft?> showPromptEditorSheet(
  BuildContext context, {
  required String title,
  String initialPrompt = '',
  int imageCount = 0,
}) {
  return showModalBottomSheet<PromptEditorDraft>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      return PromptEditorSheet(
        title: title,
        imageCount: imageCount,
        initialPrompt: initialPrompt,
      );
    },
  );
}

class PromptEditorSheet extends StatefulWidget {
  const PromptEditorSheet({
    super.key,
    required this.title,
    required this.imageCount,
    required this.initialPrompt,
  });

  final String title;
  final int imageCount;
  final String initialPrompt;

  @override
  State<PromptEditorSheet> createState() => _PromptEditorSheetState();
}

class _PromptEditorSheetState extends State<PromptEditorSheet> {
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _promptController.text.trim().isNotEmpty;
    return PixromptSheetFrame(
      key: const ValueKey('prompt.editor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.imageCount > 0
                      ? '${widget.title} (${widget.imageCount})'
                      : widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('prompt.save'),
                onPressed: canSave ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text('\u4fdd\u5b58'),
              ),
            ],
          ),
          const SizedBox(height: PixromptSpace.lg),
          SizedBox(
            height: 188,
            child: TextField(
              key: const ValueKey('prompt.input'),
              controller: _promptController,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop(
      PromptEditorDraft(prompt: _promptController.text.trim()),
    );
  }
}
