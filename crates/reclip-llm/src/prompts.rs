//! Prompt templates for LLM analysis

use crate::provider::{AnalysisRequest, AnalysisType};

/// Build analysis prompt from request
pub fn build_analysis_prompt(request: &AnalysisRequest) -> String {
    let analysis_types_str = request.analysis_types
        .iter()
        .map(|t| format!("- {}: {}", t.display_name(), type_description(t)))
        .collect::<Vec<_>>()
        .join("\n");

    let sensitivity_desc = match request.sensitivity {
        s if s < 0.3 => "lenient (only flag obvious issues)",
        s if s < 0.7 => "moderate (flag clear issues)",
        _ => "strict (flag all potential issues)",
    };

    format!(
        r#"You are an expert podcast editor analyzing a transcript for editing opportunities.

## Task
Analyze the following transcript and identify segments that should be edited out to improve the audio quality.

## Analysis Types to Look For
{analysis_types_str}

## Sensitivity
{sensitivity_desc}

## Language
{language}

## Transcript
```
{transcript}
```

## Output Format
Return a JSON array of issues found. Each item should have:
- "analysis_type": one of "filler_word", "repetition", "false_start", "long_pause", "stutter", "tangent"
- "start_time": start time in seconds (float)
- "end_time": end time in seconds (float)
- "original_text": the text that was flagged
- "suggested_replacement": suggested replacement text (null if should be removed)
- "confidence": confidence score 0.0-1.0
- "reason": brief explanation of why this was flagged

Example output:
```json
[
  {{
    "analysis_type": "filler_word",
    "start_time": 12.5,
    "end_time": 12.8,
    "original_text": "um",
    "suggested_replacement": null,
    "confidence": 0.95,
    "reason": "Common filler word that adds no content"
  }},
  {{
    "analysis_type": "repetition",
    "start_time": 45.2,
    "end_time": 46.1,
    "original_text": "the the the",
    "suggested_replacement": "the",
    "confidence": 0.9,
    "reason": "Word repeated three times"
  }}
]
```

Return ONLY the JSON array, no other text."#,
        analysis_types_str = analysis_types_str,
        sensitivity_desc = sensitivity_desc,
        language = request.language,
        transcript = request.transcript,
    )
}

/// Get description for analysis type
fn type_description(t: &AnalysisType) -> &'static str {
    match t {
        AnalysisType::FillerWord => "Words like 'um', 'uh', 'like', 'you know', '嗯', '呃' that don't add meaning",
        AnalysisType::Repetition => "Words or phrases repeated unnecessarily",
        AnalysisType::FalseStart => "Sentences that were started and then restarted differently",
        AnalysisType::LongPause => "Unusually long pauses (>2 seconds) in speech",
        AnalysisType::Stutter => "Stuttering or stumbling over words",
        AnalysisType::Tangent => "Off-topic tangents that don't contribute to the main discussion",
    }
}

/// Build summary prompt for generating episode summary
pub fn build_summary_prompt(transcript: &str, language: &str) -> String {
    format!(
        r#"You are a podcast summarizer. Create a concise summary of the following transcript.

## Language
Write the summary in: {language}

## Transcript
```
{transcript}
```

## Output
Provide:
1. A one-paragraph summary (2-3 sentences)
2. 3-5 key points discussed
3. Any action items or takeaways mentioned

Format as JSON:
```json
{{
  "summary": "...",
  "key_points": ["...", "..."],
  "takeaways": ["...", "..."]
}}
```"#,
        language = language,
        transcript = transcript,
    )
}

/// Build speaker identification prompt
pub fn build_speaker_prompt(transcript: &str, num_speakers: usize) -> String {
    format!(
        r#"You are analyzing a podcast transcript with {num_speakers} speakers.

## Task
Based on the content and speaking patterns, try to identify:
1. The role of each speaker (host, guest, interviewer, etc.)
2. Any names mentioned that might identify the speakers
3. Distinguishing characteristics of each speaker's style

## Transcript
```
{transcript}
```

## Output
Return a JSON object with speaker information:
```json
{{
  "speakers": [
    {{
      "id": "Speaker 1",
      "likely_role": "host",
      "possible_name": "John",
      "characteristics": "Asks questions, guides conversation"
    }}
  ]
}}
```"#,
        num_speakers = num_speakers,
        transcript = transcript,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_analysis_prompt() {
        let request = AnalysisRequest {
            transcript: "Hello, um, how are you?".to_string(),
            language: "en".to_string(),
            speakers: None,
            analysis_types: vec![AnalysisType::FillerWord],
            sensitivity: 0.5,
        };

        let prompt = build_analysis_prompt(&request);
        assert!(prompt.contains("Hello, um, how are you?"));
        assert!(prompt.contains("Filler Word"));
        assert!(prompt.contains("moderate"));
    }
}
