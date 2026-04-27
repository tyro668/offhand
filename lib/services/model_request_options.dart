Map<String, dynamic> buildDefaultThinkingOptions(String model) {
  final options = <String, dynamic>{
    'thinking': <String, String>{'type': 'disabled'},
  };

  final normalizedModel = model.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (RegExp(r'qwen3').hasMatch(normalizedModel)) {
    options['enable_thinking'] = false;
  }

  return options;
}