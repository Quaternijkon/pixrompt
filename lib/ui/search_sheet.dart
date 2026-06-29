import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../domain/search_filters.dart';
import 'pixrompt_design.dart';
import 'prompt_filter_page.dart';

class SearchSheet extends StatefulWidget {
  const SearchSheet({super.key, required this.controller});

  final PixromptController controller;

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: widget.controller.state.searchFilters.query,
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final filters = widget.controller.state.searchFilters;
        return PixromptSheetFrame(
          key: const ValueKey('search.sheet'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '\u641c\u7d22',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      _queryController.clear();
                      widget.controller.updateSearchFilters(
                        filters.clearAll(),
                      );
                    },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('\u6e05\u9664'),
                  ),
                ],
              ),
              const SizedBox(height: PixromptSpace.lg),
              TextField(
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Prompt \u6216\u5206\u7c7b',
                ),
                onChanged: (value) {
                  widget.controller.updateSearchFilters(
                    widget.controller.state.searchFilters.copyWith(
                      query: value,
                    ),
                  );
                },
              ),
              const SizedBox(height: PixromptSpace.md),
              DecoratedBox(
                decoration: pixromptSurfaceDecoration(
                  color: PixromptPalette.darkSurfaceHigh.withOpacity(0.50),
                  radius: PixromptRadius.md,
                  elevated: false,
                ),
                child: ListTile(
                  key: const ValueKey('search.promptListAction'),
                  leading: const Icon(Icons.format_list_bulleted),
                  title: const Text(
                    '\u6309\u5df2\u6709 Prompt \u7b5b\u9009',
                  ),
                  subtitle: Text(
                    '${widget.controller.state.prompts.length} \u4e2a Prompt',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => PromptFilterPage(
                          controller: widget.controller,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: PixromptSpace.lg),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<SortMode>(
                  segments: const [
                    ButtonSegment(
                      value: SortMode.newest,
                      icon: Icon(Icons.south),
                      label: Text('\u6700\u65b0'),
                    ),
                    ButtonSegment(
                      value: SortMode.oldest,
                      icon: Icon(Icons.north),
                      label: Text('\u6700\u65e9'),
                    ),
                    ButtonSegment(
                      value: SortMode.categoryAZ,
                      icon: Icon(Icons.sort_by_alpha),
                      label: Text('A-Z'),
                    ),
                    ButtonSegment(
                      value: SortMode.categoryZA,
                      icon: Icon(Icons.sort),
                      label: Text('Z-A'),
                    ),
                  ],
                  selected: {filters.sortMode},
                  onSelectionChanged: (selection) {
                    widget.controller.updateSearchFilters(
                      filters.copyWith(sortMode: selection.single),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
