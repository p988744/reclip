import { useState, useRef, useCallback, useEffect } from 'react';
import { open } from '@tauri-apps/plugin-dialog';
import { Header } from './components/Header';
import { Waveform } from './components/Waveform';
import { TranscriptView } from './components/TranscriptView';
import { PlaybackControls } from './components/PlaybackControls';
import { Sidebar } from './components/Sidebar';
import {
  useAudio,
  useASR,
  useDiarization,
  useLLM,
  useWaveform,
  useTranscribeProgress,
} from './hooks/useTauri';
import type {
  AudioInfo,
  TranscriptResult,
  DiarizationResult,
  AnalysisResult,
  WaveformData,
  Segment,
  ModelInfo,
  TranscribeProgress,
} from './types';

function App() {
  // State
  const [audioInfo, setAudioInfo] = useState<AudioInfo | null>(null);
  const [transcript, setTranscript] = useState<TranscriptResult | null>(null);
  const [_diarization, setDiarization] = useState<DiarizationResult | null>(null);
  const [analysis, setAnalysis] = useState<AnalysisResult | null>(null);
  const [waveformData, setWaveformData] = useState<WaveformData | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [processing, setProcessing] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);

  // Refs
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Hooks
  const { loadAudio } = useAudio();
  const { transcribe, loadAsrModel } = useASR();
  const { diarize, mergeSpeakersToTranscript } = useDiarization();
  const { analyzeTranscript } = useLLM();
  const { generateWaveform } = useWaveform();

  // Progress listener
  useTranscribeProgress(
    useCallback((p: TranscribeProgress) => {
      setProgress(p.percentage);
    }, [])
  );

  // Audio time update
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const handleTimeUpdate = () => setCurrentTime(audio.currentTime);
    const handleEnded = () => setIsPlaying(false);

    audio.addEventListener('timeupdate', handleTimeUpdate);
    audio.addEventListener('ended', handleEnded);

    return () => {
      audio.removeEventListener('timeupdate', handleTimeUpdate);
      audio.removeEventListener('ended', handleEnded);
    };
  }, []);

  // Handlers
  const handleOpenFile = async () => {
    try {
      const selected = await open({
        multiple: false,
        filters: [
          {
            name: 'Audio',
            extensions: ['mp3', 'm4a', 'wav', 'flac', 'ogg', 'aac'],
          },
        ],
      });

      console.log('Selected file:', selected);

      if (selected) {
        // Handle both string and path object formats
        const filePath = typeof selected === 'string' ? selected : (selected as any).path;

        if (!filePath) {
          console.error('No file path in selection:', selected);
          return;
        }

        setProcessing('載入音訊...');
        console.log('Loading audio from:', filePath);

        try {
          const info = await loadAudio(filePath);
          console.log('Audio info:', info);
          setAudioInfo(info);

          // Create audio element - use convertFileSrc for proper URL
          if (audioRef.current) {
            // For local files, we need to use the Tauri asset protocol
            const audioUrl = `asset://localhost/${encodeURIComponent(filePath)}`;
            console.log('Audio URL:', audioUrl);
            audioRef.current.src = audioUrl;
          }

          // Generate waveform
          setProcessing('生成波形...');
          const waveform = await generateWaveform(filePath, 100);
          console.log('Waveform generated:', waveform);
          setWaveformData(waveform);

          setProcessing(null);
          setTranscript(null);
          setDiarization(null);
          setAnalysis(null);
        } catch (loadError) {
          console.error('Failed to load audio:', loadError);
          setProcessing(null);
          alert(`無法載入音訊: ${loadError}`);
        }
      }
    } catch (error) {
      console.error('Failed to open file dialog:', error);
      setProcessing(null);
    }
  };

  const handleTranscribe = async () => {
    if (!audioInfo) return;

    try {
      setProcessing('轉錄中...');
      setProgress(0);
      const result = await transcribe(audioInfo.path, {
        language: 'zh',
        word_timestamps: true,
      });
      setTranscript(result);
      setProcessing(null);
    } catch (error) {
      console.error('Transcription failed:', error);
      setProcessing(null);
    }
  };

  const handleDiarize = async () => {
    if (!audioInfo || !transcript) return;

    try {
      setProcessing('說話者分離...');
      const result = await diarize(audioInfo.path);
      setDiarization(result);

      // Merge speakers to transcript
      const merged = await mergeSpeakersToTranscript(transcript, result);
      setTranscript(merged);
      setProcessing(null);
    } catch (error) {
      console.error('Diarization failed:', error);
      setProcessing(null);
    }
  };

  const handleAnalyze = async () => {
    if (!transcript) return;

    try {
      setProcessing('AI 分析...');
      const result = await analyzeTranscript(transcript);
      setAnalysis(result);
      setProcessing(null);
    } catch (error) {
      console.error('Analysis failed:', error);
      setProcessing(null);
    }
  };

  const handlePlayPause = () => {
    if (!audioRef.current) return;

    if (isPlaying) {
      audioRef.current.pause();
    } else {
      audioRef.current.play();
    }
    setIsPlaying(!isPlaying);
  };

  const handleSeek = (time: number) => {
    if (!audioRef.current) return;
    audioRef.current.currentTime = time;
    setCurrentTime(time);
  };

  const handleSegmentClick = (segment: Segment) => {
    handleSeek(segment.start);
  };

  const handleModelSelect = async (model: ModelInfo) => {
    if (!model.local_path) return;

    try {
      if (model.model_type === 'whisper') {
        await loadAsrModel(model.local_path);
      }
      setSidebarOpen(false);
    } catch (error) {
      console.error('Failed to load model:', error);
    }
  };

  return (
    <div className="flex flex-col h-screen bg-zinc-950 text-white">
      {/* Hidden audio element */}
      <audio ref={audioRef} />

      {/* Header */}
      <Header
        onOpenFile={handleOpenFile}
        onOpenSettings={() => setSidebarOpen(true)}
      />

      {/* Main content */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Waveform */}
        <div className="p-4">
          <Waveform
            data={waveformData}
            currentTime={currentTime}
            duration={audioInfo?.duration_seconds || 0}
            onSeek={handleSeek}
          />
        </div>

        {/* Action buttons */}
        {audioInfo && (
          <div className="flex gap-2 px-4 pb-4">
            <button
              onClick={handleTranscribe}
              disabled={!!processing}
              className="px-4 py-2 text-sm font-medium bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              開始轉錄
            </button>
            <button
              onClick={handleDiarize}
              disabled={!transcript || !!processing}
              className="px-4 py-2 text-sm font-medium bg-purple-600 rounded-lg hover:bg-purple-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              說話者分離
            </button>
            <button
              onClick={handleAnalyze}
              disabled={!transcript || !!processing}
              className="px-4 py-2 text-sm font-medium bg-green-600 rounded-lg hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              AI 分析
            </button>
          </div>
        )}

        {/* Processing indicator */}
        {processing && (
          <div className="px-4 pb-4">
            <div className="flex items-center gap-3 p-3 bg-zinc-800 rounded-lg">
              <div className="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
              <span className="text-sm text-zinc-300">{processing}</span>
              {progress > 0 && (
                <span className="text-sm text-zinc-500">{progress.toFixed(0)}%</span>
              )}
            </div>
          </div>
        )}

        {/* Transcript view */}
        <TranscriptView
          segments={transcript?.segments || []}
          editSuggestions={analysis?.edit_suggestions || []}
          currentTime={currentTime}
          onSegmentClick={handleSegmentClick}
        />
      </div>

      {/* Playback controls */}
      <PlaybackControls
        isPlaying={isPlaying}
        currentTime={currentTime}
        duration={audioInfo?.duration_seconds || 0}
        onPlayPause={handlePlayPause}
        onSeek={handleSeek}
      />

      {/* Sidebar */}
      <Sidebar
        isOpen={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        onModelSelect={handleModelSelect}
      />
    </div>
  );
}

export default App;
