class AgentBootstrapPayload {
  AgentBootstrapPayload({
    required this.ownerUserId,
    required this.background,
    required this.thinkingStyle,
    required this.riskPreference,
    required this.communicationTone,
    required this.helperStyle,
    required this.sceneTags,
    required this.principles,
    required this.avoidances,
    required this.responsePreferences,
    required this.customPrompt,
    required this.styleTags,
    required this.domainTags,
    required this.assessmentScores,
    required this.assessmentSummary,
  });

  final String ownerUserId;
  final String background;
  final String thinkingStyle;
  final String riskPreference;
  final String communicationTone;
  final String helperStyle;
  final List<String> sceneTags;
  final String principles;
  final String avoidances;
  final String responsePreferences;
  final String customPrompt;
  final List<String> styleTags;
  final List<String> domainTags;
  final Map<String, double> assessmentScores;
  final String assessmentSummary;

  Map<String, dynamic> toJson() => {
        'owner_user_id': ownerUserId,
        'background': background,
        'thinking_style': thinkingStyle,
        'risk_preference': riskPreference,
        'communication_tone': communicationTone,
        'helper_style': helperStyle,
        'scene_tags': sceneTags,
        'principles': principles,
        'avoidances': avoidances,
        'response_preferences': responsePreferences,
        'custom_prompt': customPrompt,
        'style_tags': styleTags,
        'domain_tags': domainTags,
        'assessment_scores': assessmentScores,
        'assessment_summary': assessmentSummary,
      };
}
