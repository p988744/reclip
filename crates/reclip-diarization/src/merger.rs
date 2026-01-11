//! Merge speaker diarization results with transcript

use reclip_core::{TranscriptResult, Segment, WordSegment};
use crate::{SpeakerSegment, DiarizationError};

/// Merge speaker diarization results with a transcript
///
/// This function assigns speaker labels to transcript segments and words
/// based on the diarization results.
pub fn merge_speakers_with_transcript(
    mut transcript: TranscriptResult,
    diarization: &[SpeakerSegment],
) -> Result<TranscriptResult, DiarizationError> {
    if diarization.is_empty() {
        return Err(DiarizationError::NoSpeakersDetected);
    }

    // Assign speakers to each segment
    for segment in &mut transcript.segments {
        segment.speaker = find_speaker_at_time(
            (segment.start + segment.end) / 2.0,
            diarization,
        );

        // Assign speakers to words
        for word in &mut segment.words {
            word.speaker = find_speaker_at_time(
                (word.start + word.end) / 2.0,
                diarization,
            );
        }
    }

    Ok(transcript)
}

/// Find the speaker at a given time
fn find_speaker_at_time(time: f64, diarization: &[SpeakerSegment]) -> Option<String> {
    // Find segment that contains this time
    for segment in diarization {
        if time >= segment.start && time <= segment.end {
            return Some(segment.speaker_id.clone());
        }
    }

    // If no exact match, find closest segment
    diarization
        .iter()
        .min_by(|a, b| {
            let dist_a = ((a.start + a.end) / 2.0 - time).abs();
            let dist_b = ((b.start + b.end) / 2.0 - time).abs();
            dist_a.partial_cmp(&dist_b).unwrap()
        })
        .map(|s| s.speaker_id.clone())
}

/// Merge adjacent segments with the same speaker
pub fn merge_adjacent_speaker_segments(
    mut transcript: TranscriptResult,
) -> TranscriptResult {
    if transcript.segments.len() <= 1 {
        return transcript;
    }

    let mut merged_segments: Vec<Segment> = Vec::new();

    for segment in transcript.segments.drain(..) {
        if let Some(last) = merged_segments.last_mut() {
            // Check if same speaker and adjacent (within 1 second)
            if last.speaker == segment.speaker
                && (segment.start - last.end) < 1.0
            {
                // Merge segments
                last.text = format!("{} {}", last.text, segment.text);
                last.end = segment.end;
                last.words.extend(segment.words);
                continue;
            }
        }
        merged_segments.push(segment);
    }

    transcript.segments = merged_segments;
    transcript
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_segment(start: f64, end: f64, text: &str) -> Segment {
        Segment {
            text: text.to_string(),
            start,
            end,
            speaker: None,
            words: vec![],
        }
    }

    fn create_test_speaker_segment(start: f64, end: f64, speaker: &str) -> SpeakerSegment {
        SpeakerSegment {
            start,
            end,
            speaker_id: speaker.to_string(),
            confidence: 0.9,
        }
    }

    #[test]
    fn test_merge_speakers() {
        let transcript = TranscriptResult {
            segments: vec![
                create_test_segment(0.0, 2.0, "Hello"),
                create_test_segment(3.0, 5.0, "World"),
            ],
            language: "en".to_string(),
            duration: 5.0,
        };

        let diarization = vec![
            create_test_speaker_segment(0.0, 2.5, "Speaker1"),
            create_test_speaker_segment(2.5, 5.0, "Speaker2"),
        ];

        let result = merge_speakers_with_transcript(transcript, &diarization).unwrap();

        assert_eq!(result.segments[0].speaker, Some("Speaker1".to_string()));
        assert_eq!(result.segments[1].speaker, Some("Speaker2".to_string()));
    }

    #[test]
    fn test_find_speaker_at_time() {
        let diarization = vec![
            create_test_speaker_segment(0.0, 2.0, "A"),
            create_test_speaker_segment(2.0, 4.0, "B"),
        ];

        assert_eq!(find_speaker_at_time(1.0, &diarization), Some("A".to_string()));
        assert_eq!(find_speaker_at_time(3.0, &diarization), Some("B".to_string()));
    }
}
