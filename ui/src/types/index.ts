// Audio types
export interface AudioInfo {
  path: string;
  duration_seconds: number;
  sample_rate: number;
  channels: number;
  format: string;
}

// Transcript types
export interface WordInfo {
  text: string;
  start: number;
  end: number;
  confidence: number;
}

export interface Segment {
  id: number;
  text: string;
  start: number;
  end: number;
  words: WordInfo[];
  speaker?: string;
}

export interface TranscriptResult {
  segments: Segment[];
  language: string;
  duration: number;
}

// Diarization types
export interface SpeakerSegment {
  speaker: string;
  start: number;
  end: number;
  confidence: number;
}

export interface DiarizationResult {
  segments: SpeakerSegment[];
  num_speakers: number;
}

// Analysis types
export interface EditSuggestion {
  segment_id: number;
  edit_type: string;
  reason: string;
  start: number;
  end: number;
  original_text: string;
  suggested_action: string;
}

export interface AnalysisResult {
  summary: string;
  edit_suggestions: EditSuggestion[];
  total_removable_duration: number;
}

// Model types
export interface ModelInfo {
  id: string;
  name: string;
  model_type: string;
  size_bytes: number;
  description: string;
  is_downloaded: boolean;
  local_path: string | null;
}

// Waveform types
export interface WaveformData {
  peaks: number[];
  sample_rate: number;
  channels: number;
}

// Language types
export interface LanguageInfo {
  code: string;
  name: string;
}

// Progress events
export interface TranscribeProgress {
  percentage: number;
  current_segment: number;
  total_segments: number;
  current_text?: string;
}

export interface DiarizationProgress {
  stage: string;
  percentage: number;
}

export interface ModelDownloadProgress {
  model_id: string;
  progress: number;
}

// LLM types
export type LlmProviderType = 'claude' | 'ollama';

export interface LlmConfig {
  provider: LlmProviderType;
  api_key?: string;
  model?: string;
  base_url?: string;
}
