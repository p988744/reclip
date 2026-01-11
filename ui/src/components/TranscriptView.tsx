import type { Segment, EditSuggestion } from '../types';

interface TranscriptViewProps {
  segments: Segment[];
  editSuggestions: EditSuggestion[];
  currentTime: number;
  onSegmentClick: (segment: Segment) => void;
}

export function TranscriptView({
  segments,
  editSuggestions,
  currentTime,
  onSegmentClick,
}: TranscriptViewProps) {
  const getSuggestionForSegment = (segmentId: number) => {
    return editSuggestions.find((s) => s.segment_id === segmentId);
  };

  const isCurrentSegment = (segment: Segment) => {
    return currentTime >= segment.start && currentTime <= segment.end;
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const getSpeakerColor = (speaker?: string) => {
    if (!speaker) return 'bg-zinc-700';
    const colors = [
      'bg-blue-600',
      'bg-green-600',
      'bg-purple-600',
      'bg-orange-600',
      'bg-pink-600',
      'bg-cyan-600',
    ];
    const index = parseInt(speaker.replace(/\D/g, ''), 10) || 0;
    return colors[index % colors.length];
  };

  if (segments.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center text-zinc-500">
        <div className="text-center">
          <p>尚無轉錄結果</p>
          <p className="text-sm mt-1">載入音訊並開始轉錄</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-2">
      {segments.map((segment) => {
        const suggestion = getSuggestionForSegment(segment.id);
        const isCurrent = isCurrentSegment(segment);

        return (
          <div
            key={segment.id}
            onClick={() => onSegmentClick(segment)}
            className={`
              p-3 rounded-lg cursor-pointer transition-all
              ${isCurrent ? 'bg-blue-900/30 border border-blue-500' : 'bg-zinc-800 hover:bg-zinc-700'}
              ${suggestion ? 'border-l-4 border-l-yellow-500' : ''}
            `}
          >
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-zinc-500">
                {formatTime(segment.start)} - {formatTime(segment.end)}
              </span>
              {segment.speaker && (
                <span className={`text-xs px-2 py-0.5 rounded-full text-white ${getSpeakerColor(segment.speaker)}`}>
                  {segment.speaker}
                </span>
              )}
              {suggestion && (
                <span className="text-xs px-2 py-0.5 rounded-full bg-yellow-600 text-white">
                  {suggestion.edit_type}
                </span>
              )}
            </div>
            <p className={`text-sm ${suggestion ? 'text-yellow-200' : 'text-white'}`}>
              {segment.text}
            </p>
            {suggestion && (
              <p className="text-xs text-yellow-400 mt-1">
                建議：{suggestion.reason}
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}
