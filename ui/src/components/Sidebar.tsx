import { useState, useEffect } from 'react';
import { useModels, useModelDownloadProgress } from '../hooks/useTauri';
import type { ModelInfo, ModelDownloadProgress } from '../types';

interface SidebarProps {
  isOpen: boolean;
  onClose: () => void;
  onModelSelect: (model: ModelInfo) => void;
}

export function Sidebar({ isOpen, onClose, onModelSelect }: SidebarProps) {
  const { listModels, downloadModel, deleteModel, getCacheSize } = useModels();
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [cacheSize, setCacheSize] = useState(0);
  const [downloadProgress, setDownloadProgress] = useState<Record<string, number>>({});

  useModelDownloadProgress((progress: ModelDownloadProgress) => {
    setDownloadProgress((prev) => ({
      ...prev,
      [progress.model_id]: progress.progress,
    }));
  });

  const loadModels = async () => {
    try {
      const [modelList, size] = await Promise.all([listModels(), getCacheSize()]);
      setModels(modelList);
      setCacheSize(size);
    } catch (error) {
      console.error('Failed to load models:', error);
    }
  };

  useEffect(() => {
    if (isOpen) {
      loadModels();
    }
  }, [isOpen]);

  const handleDownload = async (model: ModelInfo) => {
    try {
      await downloadModel(model.id);
      await loadModels();
    } catch (error) {
      console.error('Download failed:', error);
    }
  };

  const handleDelete = async (model: ModelInfo) => {
    try {
      await deleteModel(model.id);
      await loadModels();
    } catch (error) {
      console.error('Delete failed:', error);
    }
  };

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  };

  const whisperModels = models.filter((m) => m.model_type === 'whisper');
  const diarizationModels = models.filter((m) => m.model_type === 'diarization');

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex">
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />
      <div className="relative w-80 h-full bg-zinc-900 border-r border-zinc-700 overflow-y-auto ml-auto">
        <div className="sticky top-0 bg-zinc-900 border-b border-zinc-700 p-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-white">模型管理</h2>
          <button onClick={onClose} className="text-zinc-400 hover:text-white">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="p-4">
          <div className="text-sm text-zinc-400 mb-4">
            快取大小：{formatSize(cacheSize)}
          </div>

          <div className="space-y-6">
            <div>
              <h3 className="text-sm font-medium text-zinc-300 mb-2">Whisper 模型</h3>
              <div className="space-y-2">
                {whisperModels.map((model) => (
                  <ModelCard
                    key={model.id}
                    model={model}
                    progress={downloadProgress[model.id]}
                    onDownload={() => handleDownload(model)}
                    onDelete={() => handleDelete(model)}
                    onSelect={() => onModelSelect(model)}
                    formatSize={formatSize}
                  />
                ))}
              </div>
            </div>

            <div>
              <h3 className="text-sm font-medium text-zinc-300 mb-2">說話者分離模型</h3>
              <div className="space-y-2">
                {diarizationModels.map((model) => (
                  <ModelCard
                    key={model.id}
                    model={model}
                    progress={downloadProgress[model.id]}
                    onDownload={() => handleDownload(model)}
                    onDelete={() => handleDelete(model)}
                    onSelect={() => onModelSelect(model)}
                    formatSize={formatSize}
                  />
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

interface ModelCardProps {
  model: ModelInfo;
  progress?: number;
  onDownload: () => void;
  onDelete: () => void;
  onSelect: () => void;
  formatSize: (bytes: number) => string;
}

function ModelCard({ model, progress, onDownload, onDelete, onSelect, formatSize }: ModelCardProps) {
  const isDownloading = progress !== undefined && progress < 100;

  return (
    <div className="p-3 bg-zinc-800 rounded-lg">
      <div className="flex items-start justify-between mb-1">
        <div>
          <h4 className="text-sm font-medium text-white">{model.name}</h4>
          <p className="text-xs text-zinc-500">{formatSize(model.size_bytes)}</p>
        </div>
        {model.is_downloaded ? (
          <div className="flex gap-1">
            <button
              onClick={onSelect}
              className="text-xs px-2 py-1 bg-blue-600 text-white rounded hover:bg-blue-700"
            >
              使用
            </button>
            <button
              onClick={onDelete}
              className="text-xs px-2 py-1 bg-red-600/20 text-red-400 rounded hover:bg-red-600/30"
            >
              刪除
            </button>
          </div>
        ) : (
          <button
            onClick={onDownload}
            disabled={isDownloading}
            className="text-xs px-2 py-1 bg-zinc-700 text-white rounded hover:bg-zinc-600 disabled:opacity-50"
          >
            {isDownloading ? `${progress?.toFixed(0)}%` : '下載'}
          </button>
        )}
      </div>
      <p className="text-xs text-zinc-400">{model.description}</p>
      {isDownloading && (
        <div className="mt-2 h-1 bg-zinc-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-blue-500 transition-all"
            style={{ width: `${progress}%` }}
          />
        </div>
      )}
    </div>
  );
}
