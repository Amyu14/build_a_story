class CompletedSection {
  final String storyText;
  final String base64Image;
  final List<String> choices;
  final String previousChoice;

  CompletedSection(
    {
      required this.storyText, 
      required this.base64Image,
      required this.choices,
      required this.previousChoice
    }
  );
}
