/**
 * CogniForge Virtual API client.
 * Talks to the inference server (virtual_api.py) to generate videos.
 */

const API_URL = import.meta.env.VITE_VIRTUAL_API_URL || 'http://localhost:8000';

export interface GenerationRequest {
  prompt: string;
  duration_minutes: number;
  width?: number;
  height?: number;
  fps?: number;
  seed?: number;
  guidance_scale?: number;
}

export interface JobStatus {
  job_id: string;
  status: 'queued' | 'processing' | 'completed' | 'failed';
  video_url?: string;
  error?: string;
  progress?: number;
}

export async function generateVideo(req: GenerationRequest): Promise<{ job_id: string; status: string }> {
  const res = await fetch(`${API_URL}/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || 'Generation request failed');
  }
  return res.json();
}

export async function getJobStatus(jobId: string): Promise<JobStatus> {
  const res = await fetch(`${API_URL}/status/${jobId}`);
  if (!res.ok) throw new Error('Failed to fetch job status');
  return res.json();
}

export async function getVideoUrl(jobId: string): string {
  return `${API_URL}/download/${jobId}`;
}

export async function getHealth(): Promise<any> {
  const res = await fetch(`${API_URL}/health`);
  if (!res.ok) throw new Error('Health check failed');
  return res.json();
}

/**
 * Poll job status until completed or failed.
 * Calls onProgress with the latest status on each poll.
 */
export async function waitForJob(
  jobId: string,
  onProgress?: (status: JobStatus) => void,
  pollIntervalMs = 2000,
): Promise<JobStatus> {
  return new Promise((resolve, reject) => {
    const poll = async () => {
      try {
        const status = await getJobStatus(jobId);
        onProgress?.(status);
        if (status.status === 'completed') {
          resolve(status);
        } else if (status.status === 'failed') {
          reject(new Error(status.error || 'Generation failed'));
        } else {
          setTimeout(poll, pollIntervalMs);
        }
      } catch (err) {
        reject(err);
      }
    };
    poll();
  });
}
