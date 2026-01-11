import { useRef, useEffect } from 'react';
import type { WaveformData } from '../types';

interface WaveformProps {
  data: WaveformData | null;
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
}

export function Waveform({ data, currentTime, duration, onSeek }: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !data) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const { width, height } = canvas;
    const { peaks } = data;

    // Clear canvas
    ctx.fillStyle = '#18181b';
    ctx.fillRect(0, 0, width, height);

    // Draw waveform
    const barWidth = width / peaks.length;
    const centerY = height / 2;

    ctx.fillStyle = '#3b82f6';
    peaks.forEach((peak, i) => {
      const barHeight = peak * height * 0.8;
      const x = i * barWidth;
      ctx.fillRect(x, centerY - barHeight / 2, Math.max(1, barWidth - 1), barHeight);
    });

    // Draw playhead
    if (duration > 0) {
      const playheadX = (currentTime / duration) * width;
      ctx.fillStyle = '#ef4444';
      ctx.fillRect(playheadX - 1, 0, 2, height);
    }
  }, [data, currentTime, duration]);

  const handleClick = (e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas || duration <= 0) return;

    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const time = (x / rect.width) * duration;
    onSeek(time);
  };

  return (
    <div className="w-full h-24 bg-zinc-900 rounded-lg overflow-hidden">
      {data ? (
        <canvas
          ref={canvasRef}
          className="w-full h-full cursor-pointer"
          width={1200}
          height={96}
          onClick={handleClick}
        />
      ) : (
        <div className="flex items-center justify-center h-full text-zinc-500">
          載入音訊以顯示波形
        </div>
      )}
    </div>
  );
}
