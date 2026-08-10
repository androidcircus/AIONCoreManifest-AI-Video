import { useState, useCallback } from 'react';
import { generateVideo, waitForJob, getVideoUrl, type JobStatus } from '../api/virtualApi';

export function VideoGenerator() {
  const [prompt, setPrompt] = useState('');
  const [duration, setDuration] = useState(10);
  const [width, setWidth] = useState(1920);
  const [height, setHeight] = useState(1080);
  const [fps, setFps] = useState(24);
  const [seed, setSeed] = useState(42);
  const [jobStatus, setJobStatus] = useState<JobStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [videoUrl, setVideoUrl] = useState<string | null>(null);

  const handleGenerate = useCallback(async () => {
    if (!prompt.trim()) {
      setError('Please enter a prompt');
      return;
    }
    setLoading(true);
    setError(null);
    setVideoUrl(null);
    setJobStatus(null);

    try {
      const { job_id } = await generateVideo({
        prompt,
        duration_minutes: duration,
        width,
        height,
        fps,
        seed,
      });

      setJobStatus({ job_id, status: 'processing', progress: 0 });

      const finalStatus = await waitForJob(job_id, (s) => {
        setJobStatus(s);
      });

      setVideoUrl(getVideoUrl(job_id));
      setJobStatus(finalStatus);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Generation failed');
    } finally {
      setLoading(false);
    }
  }, [prompt, duration, width, height, fps, seed]);

  const progress = jobStatus?.progress ? Math.round(jobStatus.progress * 100) : 0;

  return (
    <div style={{ maxWidth: 720, margin: '0 auto', padding: 24 }}>
      <h1>CogniForge Video Generator</h1>

      <div style={{ marginBottom: 16 }}>
        <label style={{ display: 'block', marginBottom: 4 }}>Prompt</label>
        <textarea
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          placeholder="Describe your video..."
          style={{ width: '100%', minHeight: 80, padding: 8, borderRadius: 4, border: '1px solid #ccc' }}
        />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <div>
          <label>Duration (minutes)</label>
          <input type="number" value={duration} min={1} max={30}
            onChange={(e) => setDuration(Number(e.target.value))} style={{ width: '100%', padding: 8 }} />
        </div>
        <div>
          <label>Seed</label>
          <input type="number" value={seed}
            onChange={(e) => setSeed(Number(e.target.value))} style={{ width: '100%', padding: 8 }} />
        </div>
        <div>
          <label>Width</label>
          <input type="number" value={width} step={2}
            onChange={(e) => setWidth(Number(e.target.value))} style={{ width: '100%', padding: 8 }} />
        </div>
        <div>
          <label>Height</label>
          <input type="number" value={height} step={2}
            onChange={(e) => setHeight(Number(e.target.value))} style={{ width: '100%', padding: 8 }} />
        </div>
      </div>

      <button
        onClick={handleGenerate}
        disabled={loading}
        style={{
          padding: '12px 32px', borderRadius: 6, border: 'none',
          background: loading ? '#666' : '#2563eb', color: '#fff',
          fontSize: 16, cursor: loading ? 'not-allowed' : 'pointer',
        }}
      >
        {loading ? `Generating... ${progress}%` : 'Generate Video'}
      </button>

      {error && (
        <div style={{ marginTop: 16, padding: 12, background: '#fee', borderRadius: 4, color: '#c00' }}>
          {error}
        </div>
      )}

      {jobStatus && jobStatus.status === 'processing' && (
        <div style={{ marginTop: 16 }}>
          <div style={{ background: '#e0e0e0', borderRadius: 4, height: 8, overflow: 'hidden' }}>
            <div style={{ background: '#2563eb', height: '100%', width: `${progress}%`, transition: 'width 0.5s' }} />
          </div>
          <p style={{ marginTop: 4, fontSize: 14, color: '#666' }}>{progress}% complete</p>
        </div>
      )}

      {videoUrl && (
        <div style={{ marginTop: 16 }}>
          <h3>Result</h3>
          <video src={videoUrl} controls style={{ width: '100%', borderRadius: 8 }} />
          <a href={videoUrl} download style={{ display: 'inline-block', marginTop: 8, color: '#2563eb' }}>
            Download MP4
          </a>
        </div>
      )}
    </div>
  );
}
