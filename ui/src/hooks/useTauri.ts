import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import { useEffect, useCallback } from 'react';
import type {
  AudioInfo,
  TranscriptResult,
  DiarizationResult,
  AnalysisResult,
  ModelInfo,
  WaveformData,
  LanguageInfo,
  LlmConfig,
  TranscribeProgress,
  DiarizationProgress,
  ModelDownloadProgress,
} from '../types';

// Audio commands
export function useAudio() {
  const getAudioInfo = useCallback(async (path: string): Promise<AudioInfo> => {
    return invoke('get_audio_info', { path });
  }, []);

  // loadAudio is the same as getAudioInfo but with a more semantic name
  const loadAudio = useCallback(async (path: string): Promise<AudioInfo> => {
    return invoke('get_audio_info', { path });
  }, []);

  return { getAudioInfo, loadAudio };
}

// ASR commands
export function useASR() {
  const getLanguages = useCallback(async (): Promise<LanguageInfo[]> => {
    return invoke('get_languages');
  }, []);

  const loadAsrModel = useCallback(async (modelPath: string): Promise<void> => {
    return invoke('load_asr_model', { modelPath });
  }, []);

  const unloadAsrModel = useCallback(async (): Promise<void> => {
    return invoke('unload_asr_model');
  }, []);

  const transcribe = useCallback(async (
    audioPath: string,
    options?: { language?: string; word_timestamps?: boolean; threads?: number }
  ): Promise<TranscriptResult> => {
    return invoke('transcribe', { audioPath, options });
  }, []);

  return { getLanguages, loadAsrModel, unloadAsrModel, transcribe };
}

// Diarization commands
export function useDiarization() {
  const diarize = useCallback(async (
    audioPath: string,
    options?: { minSpeakers?: number; maxSpeakers?: number }
  ): Promise<DiarizationResult> => {
    return invoke('diarize', { audioPath, options });
  }, []);

  const loadDiarizationModels = useCallback(async (
    segmentationPath: string,
    embeddingPath: string
  ): Promise<void> => {
    return invoke('load_diarization_models', { segmentationPath, embeddingPath });
  }, []);

  const mergeSpeakersToTranscript = useCallback(async (
    transcript: TranscriptResult,
    diarization: DiarizationResult
  ): Promise<TranscriptResult> => {
    return invoke('merge_speakers', { transcript, diarization });
  }, []);

  return { diarize, loadDiarizationModels, mergeSpeakersToTranscript };
}

// LLM commands
export function useLLM() {
  const configureLlm = useCallback(async (config: LlmConfig): Promise<void> => {
    return invoke('configure_llm', { config });
  }, []);

  const analyzeTranscript = useCallback(async (
    transcript: TranscriptResult,
    prompt?: string
  ): Promise<AnalysisResult> => {
    return invoke('analyze_transcript', { transcript, prompt });
  }, []);

  return { configureLlm, analyzeTranscript };
}

// Model management commands
export function useModels() {
  const listModels = useCallback(async (): Promise<ModelInfo[]> => {
    return invoke('list_models');
  }, []);

  const downloadModel = useCallback(async (modelId: string): Promise<string> => {
    return invoke('download_model', { modelId });
  }, []);

  const deleteModel = useCallback(async (modelId: string): Promise<void> => {
    return invoke('delete_model', { modelId });
  }, []);

  const getCacheSize = useCallback(async (): Promise<number> => {
    return invoke('get_cache_size');
  }, []);

  const clearModelCache = useCallback(async (): Promise<void> => {
    return invoke('clear_model_cache');
  }, []);

  return { listModels, downloadModel, deleteModel, getCacheSize, clearModelCache };
}

// Waveform commands
export function useWaveform() {
  const generateWaveform = useCallback(async (
    audioPath: string,
    samplesPerSecond?: number
  ): Promise<WaveformData> => {
    return invoke('generate_waveform', { audioPath, samplesPerSecond });
  }, []);

  return { generateWaveform };
}

// Event listeners
export function useTranscribeProgress(
  onProgress: (progress: TranscribeProgress) => void
) {
  useEffect(() => {
    let unlisten: UnlistenFn | undefined;

    listen<TranscribeProgress>('asr:transcribe-progress', (event) => {
      onProgress(event.payload);
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      unlisten?.();
    };
  }, [onProgress]);
}

export function useDiarizationProgress(
  onProgress: (progress: DiarizationProgress) => void
) {
  useEffect(() => {
    let unlisten: UnlistenFn | undefined;

    listen<DiarizationProgress>('diarization:progress', (event) => {
      onProgress(event.payload);
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      unlisten?.();
    };
  }, [onProgress]);
}

export function useModelDownloadProgress(
  onProgress: (progress: ModelDownloadProgress) => void
) {
  useEffect(() => {
    let unlisten: UnlistenFn | undefined;

    listen<ModelDownloadProgress>('model:download-progress', (event) => {
      onProgress(event.payload);
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      unlisten?.();
    };
  }, [onProgress]);
}
