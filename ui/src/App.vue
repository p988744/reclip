<script setup lang="ts">
import { ref, computed } from 'vue'

declare global {
  interface Window {
    __TAURI__?: {
      core: {
        invoke: (cmd: string, args?: any) => Promise<any>
      }
    }
  }
}

const invoke = window.__TAURI__?.core?.invoke

// 狀態
const audioPath = ref('')
const audioInfo = ref<any>(null)
const isProcessing = ref(false)
const processingStep = ref('')
const analysisResult = ref<any>(null)
const editReport = ref<any>(null)
const error = ref('')

// 設定
const settings = ref({
  language: 'zh',
  whisperModel: 'large-v3',
  crossfadeMs: 30,
  minRemovalMs: 100,
})

// 計算屬性
const canProcess = computed(() => audioPath.value && !isProcessing.value)
const hasResult = computed(() => analysisResult.value !== null)

// 選擇檔案
async function selectFile() {
  if (!invoke) {
    error.value = 'Tauri API 不可用'
    return
  }

  try {
    // 使用 Tauri dialog
    const result = await invoke('plugin:dialog|open', {
      multiple: false,
      filters: [{
        name: 'Audio',
        extensions: ['wav', 'mp3', 'flac', 'm4a', 'ogg']
      }]
    })

    if (result) {
      audioPath.value = result as string
      await loadAudioInfo()
    }
  } catch (e: any) {
    error.value = e.toString()
  }
}

// 載入音訊資訊
async function loadAudioInfo() {
  if (!invoke || !audioPath.value) return

  try {
    audioInfo.value = await invoke('get_audio_info', { path: audioPath.value })
    error.value = ''
  } catch (e: any) {
    error.value = e.toString()
  }
}

// 處理音訊（這裡需要呼叫 Python 後端）
async function processAudio() {
  if (!canProcess.value) return

  isProcessing.value = true
  error.value = ''

  try {
    processingStep.value = '轉錄中...'
    // TODO: 呼叫 Python WhisperX

    processingStep.value = '分析中...'
    // TODO: 呼叫 Claude API

    processingStep.value = '完成'
  } catch (e: any) {
    error.value = e.toString()
  } finally {
    isProcessing.value = false
    processingStep.value = ''
  }
}

// 執行剪輯
async function executeEdit() {
  if (!invoke || !analysisResult.value) return

  try {
    const outputPath = audioPath.value.replace(/\.[^.]+$/, '_edited.wav')

    editReport.value = await invoke('edit_audio', {
      audioPath: audioPath.value,
      outputPath,
      analysis: analysisResult.value,
      config: {
        crossfade_ms: settings.value.crossfadeMs,
        min_removal_ms: settings.value.minRemovalMs,
        merge_gap_ms: 50,
        zero_crossing_search_ms: 5,
      }
    })

    error.value = ''
  } catch (e: any) {
    error.value = e.toString()
  }
}

// 匯出報告
async function exportReport(format: 'json' | 'edl' | 'markers') {
  if (!invoke || !editReport.value) return

  try {
    const basePath = audioPath.value.replace(/\.[^.]+$/, '')

    switch (format) {
      case 'json':
        await invoke('export_json', {
          report: editReport.value,
          outputPath: `${basePath}_report.json`,
          pretty: true,
        })
        break
      case 'edl':
        await invoke('export_edl', {
          report: editReport.value,
          outputPath: `${basePath}.edl`,
          fps: 30.0,
        })
        break
      case 'markers':
        await invoke('export_markers', {
          report: editReport.value,
          outputPath: `${basePath}_markers.csv`,
          format: 'csv',
        })
        break
    }
  } catch (e: any) {
    error.value = e.toString()
  }
}

// 格式化時間
function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}:${secs.toString().padStart(2, '0')}`
}
</script>

<template>
  <div class="app">
    <!-- 頂部標題 -->
    <header class="header">
      <h1>Reclip</h1>
      <span class="subtitle">Podcast 自動剪輯工具</span>
    </header>

    <!-- 主要內容 -->
    <main class="main">
      <!-- 左側：輸入與設定 -->
      <section class="panel input-panel">
        <h2>輸入</h2>

        <!-- 檔案選擇 -->
        <div class="file-input">
          <button @click="selectFile" class="btn btn-primary">
            選擇音訊檔案
          </button>
          <span v-if="audioPath" class="file-path">{{ audioPath }}</span>
        </div>

        <!-- 音訊資訊 -->
        <div v-if="audioInfo" class="audio-info">
          <h3>音訊資訊</h3>
          <div class="info-grid">
            <span>時長</span>
            <span>{{ formatDuration(audioInfo.duration) }}</span>
            <span>取樣率</span>
            <span>{{ audioInfo.sample_rate }} Hz</span>
            <span>聲道</span>
            <span>{{ audioInfo.channels }}</span>
          </div>
        </div>

        <!-- 設定 -->
        <div class="settings">
          <h3>設定</h3>

          <label>
            語言
            <select v-model="settings.language">
              <option value="zh">中文</option>
              <option value="en">English</option>
              <option value="ja">日本語</option>
            </select>
          </label>

          <label>
            Whisper 模型
            <select v-model="settings.whisperModel">
              <option value="large-v3">large-v3 (最準確)</option>
              <option value="medium">medium</option>
              <option value="small">small (最快)</option>
            </select>
          </label>

          <label>
            Crossfade (ms)
            <input type="number" v-model.number="settings.crossfadeMs" min="0" max="100" />
          </label>
        </div>

        <!-- 處理按鈕 -->
        <button
          @click="processAudio"
          :disabled="!canProcess"
          class="btn btn-primary btn-large"
        >
          <span v-if="isProcessing">{{ processingStep }}</span>
          <span v-else>開始處理</span>
        </button>
      </section>

      <!-- 右側：結果 -->
      <section class="panel result-panel">
        <h2>結果</h2>

        <!-- 錯誤訊息 -->
        <div v-if="error" class="error">
          {{ error }}
        </div>

        <!-- 分析結果 -->
        <div v-if="analysisResult" class="analysis-result">
          <h3>分析結果</h3>
          <div class="stats">
            <div class="stat">
              <span class="stat-value">{{ formatDuration(analysisResult.original_duration) }}</span>
              <span class="stat-label">原始長度</span>
            </div>
            <div class="stat">
              <span class="stat-value">{{ formatDuration(analysisResult.removed_duration) }}</span>
              <span class="stat-label">移除長度</span>
            </div>
            <div class="stat">
              <span class="stat-value">{{ analysisResult.removals.length }}</span>
              <span class="stat-label">編輯點</span>
            </div>
          </div>

          <!-- 編輯列表 -->
          <div class="edit-list">
            <h4>待移除區間</h4>
            <div
              v-for="(removal, index) in analysisResult.removals.slice(0, 10)"
              :key="index"
              class="edit-item"
            >
              <span class="edit-time">
                {{ removal.start.toFixed(2) }}s - {{ removal.end.toFixed(2) }}s
              </span>
              <span class="edit-reason">{{ removal.reason }}</span>
              <span class="edit-text">{{ removal.text }}</span>
            </div>
            <div v-if="analysisResult.removals.length > 10" class="more">
              還有 {{ analysisResult.removals.length - 10 }} 項...
            </div>
          </div>

          <button @click="executeEdit" class="btn btn-success">
            執行剪輯
          </button>
        </div>

        <!-- 編輯報告 -->
        <div v-if="editReport" class="edit-report">
          <h3>剪輯完成</h3>
          <p>
            輸出: {{ editReport.output_path }}
          </p>
          <p>
            節省: {{ formatDuration(editReport.original_duration - editReport.edited_duration) }}
          </p>

          <div class="export-buttons">
            <button @click="exportReport('json')" class="btn">匯出 JSON</button>
            <button @click="exportReport('edl')" class="btn">匯出 EDL</button>
            <button @click="exportReport('markers')" class="btn">匯出標記</button>
          </div>
        </div>
      </section>
    </main>
  </div>
</template>

<style scoped>
.app {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: #1a1a2e;
  color: #eee;
}

.header {
  padding: 1rem 2rem;
  background: #16213e;
  display: flex;
  align-items: baseline;
  gap: 1rem;
}

.header h1 {
  font-size: 1.5rem;
  font-weight: 600;
}

.subtitle {
  color: #888;
  font-size: 0.9rem;
}

.main {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
  padding: 1rem;
  overflow: hidden;
}

.panel {
  background: #16213e;
  border-radius: 8px;
  padding: 1.5rem;
  overflow-y: auto;
}

.panel h2 {
  margin-bottom: 1rem;
  font-size: 1.2rem;
  color: #0f4c75;
}

.panel h3 {
  margin: 1rem 0 0.5rem;
  font-size: 1rem;
  color: #3282b8;
}

.file-input {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1rem;
}

.file-path {
  color: #888;
  font-size: 0.85rem;
  word-break: break-all;
}

.btn {
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.9rem;
  transition: background 0.2s;
}

.btn-primary {
  background: #0f4c75;
  color: white;
}

.btn-primary:hover {
  background: #1565a0;
}

.btn-primary:disabled {
  background: #444;
  cursor: not-allowed;
}

.btn-success {
  background: #2e7d32;
  color: white;
}

.btn-success:hover {
  background: #388e3c;
}

.btn-large {
  width: 100%;
  padding: 1rem;
  font-size: 1rem;
  margin-top: 1rem;
}

.audio-info {
  background: #0f3460;
  padding: 1rem;
  border-radius: 4px;
  margin-bottom: 1rem;
}

.info-grid {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.5rem;
}

.info-grid span:nth-child(odd) {
  color: #888;
}

.settings {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.settings label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.9rem;
  color: #888;
}

.settings select,
.settings input {
  padding: 0.5rem;
  border: 1px solid #333;
  border-radius: 4px;
  background: #0f3460;
  color: #eee;
}

.error {
  background: #5c1c1c;
  color: #ff8a8a;
  padding: 1rem;
  border-radius: 4px;
  margin-bottom: 1rem;
}

.stats {
  display: flex;
  gap: 1rem;
  margin: 1rem 0;
}

.stat {
  flex: 1;
  background: #0f3460;
  padding: 1rem;
  border-radius: 4px;
  text-align: center;
}

.stat-value {
  display: block;
  font-size: 1.5rem;
  font-weight: 600;
  color: #3282b8;
}

.stat-label {
  font-size: 0.8rem;
  color: #888;
}

.edit-list {
  max-height: 300px;
  overflow-y: auto;
  margin: 1rem 0;
}

.edit-item {
  display: grid;
  grid-template-columns: auto auto 1fr;
  gap: 0.5rem;
  padding: 0.5rem;
  background: #0f3460;
  border-radius: 4px;
  margin-bottom: 0.25rem;
  font-size: 0.85rem;
}

.edit-time {
  color: #888;
  font-family: monospace;
}

.edit-reason {
  background: #1a1a2e;
  padding: 0.1rem 0.5rem;
  border-radius: 2px;
  font-size: 0.75rem;
}

.edit-text {
  color: #aaa;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.more {
  color: #666;
  font-size: 0.85rem;
  padding: 0.5rem;
}

.export-buttons {
  display: flex;
  gap: 0.5rem;
  margin-top: 1rem;
}

.export-buttons .btn {
  background: #333;
}

.export-buttons .btn:hover {
  background: #444;
}
</style>
