"""
F5-TTS singleton wrapper. Loads model once on first use, holds it
in CUDA memory, exposes a single `synthesize()` call. Tracks last-use
timestamp so the FastAPI app can shut itself down on idle.

Based on: https://github.com/SWivid/f5-tts
"""
from __future__ import annotations

import io
import os
import threading
import time
import traceback
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import soundfile as sf
import torch


@dataclass
class SynthesisResult:
    wav_bytes: bytes
    sample_rate: int
    audio_duration_seconds: float
    generation_time_seconds: float
    rtf: float


class F5Synthesizer:
    """Thread-safe singleton. CUDA model stays resident."""

    _instance_lock = threading.Lock()
    _instance: "F5Synthesizer | None" = None

    @classmethod
    def shared(cls) -> "F5Synthesizer":
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def __init__(self) -> None:
        self.model_path = os.environ.get("F5_MODEL_PATH", "SWivid/F5-TTS_v1_Base")
        self.device = os.environ.get("F5_DEVICE") or (
            "cuda" if torch.cuda.is_available()
            else "mps" if torch.backends.mps.is_available()
            else "cpu"
        ))
        self.sample_rate = 24_000
        self._render_lock = threading.Lock()
        self._loaded = False
        self.last_use_ts = time.time()
        self.model = None
        self.processor = None
        self.vocoder = None

    def ensure_loaded(self) -> None:
        if self._loaded:
            return
        with self._render_lock:
            if self._loaded:
                return
            self._load()
            self._loaded = True

    def _load(self) -> None:
        try:
            from f5_tts import F5TTS, F5Processor
            from f5_tts.utils import load_vocoder
        except ImportError as e:
            raise RuntimeError("F5-TTS not installed. Run 'pip install git+https://github.com/SWivid/f5-tts'")

        if self.device == "cuda":
            load_dtype = torch.bfloat16
        else:
            load_dtype = torch.float32

        print(f"[F5Synthesizer] Loading model from {self.model_path} on {self.device}...", flush=True)
        
        try:
            self.processor = F5Processor.from_pretrained(self.model_path)
            self.model = F5TTS.from_pretrained(self.model_path, torch_dtype=load_dtype)
            self.vocoder = load_vocoder(self.model_path, device=self.device)
            
            if self.device == "mps":
                self.model.to("mps")
                self.vocoder.to("mps")
            elif self.device != "cpu":
                self.model.to(self.device)
                self.vocoder.to(self.device)
                
            self.model.eval()
            
        except Exception:
            traceback.print_exc()
            raise RuntimeError(f"Failed to load F5-TTS model from {self.model_path}")

    def synthesize(
        self,
        text: str,
        reference_audio_bytes: bytes,
        reference_text: str,
        cfg_scale: float = 2.0,
        nfe_steps: int = 32,
        seed: int | None = None,
        speaker_label: str = "Jarvis",
    ) -> SynthesisResult:
        self.ensure_loaded()

        with self._render_lock:
            if seed is not None:
                torch.manual_seed(seed)
                if torch.cuda.is_available():
                    torch.cuda.manual_seed_all(seed)

            ref_path = self._materialize_reference_wav(reference_audio_bytes)

            try:
                t0 = time.time()
                
                # F5-TTS synthesis flow
                inputs = self.processor(
                    text=text,
                    reference_audio_path=ref_path,
                    reference_transcription=reference_text,
                    return_tensors="pt"
                )
                
                # Move inputs to target device
                target_device = self.device if self.device != "cpu" else "cpu"
                for key in inputs:
                    if torch.is_tensor(inputs[key]):
                        inputs[key] = inputs[key].to(target_device)
                
                # Generate mel spectrogram
                with torch.no_grad():
                    mel_outputs = self.model.generate(
                        **inputs,
                        cfg_scale=cfg_scale,
                        nfe_steps=nfe_steps
                    )
                
                # Convert mel to waveform
                with torch.no_grad():
                    audio = self.vocoder(mel_outputs).squeeze()
                    audio = audio.cpu().numpy()
                
                gen_time = time.time() - t0

                # Normalize and clip audio
                audio = np.clip(audio, -1.0, 1.0)

                buf = io.BytesIO()
                sf.write(buf, audio, self.sample_rate, format="WAV", subtype="PCM_16")
                wav_bytes = buf.getvalue()

                duration = len(audio) / float(self.sample_rate)
                rtf = gen_time / duration if duration > 0 else float("inf")
                self.last_use_ts = time.time()
                return SynthesisResult(
                    wav_bytes=wav_bytes,
                    sample_rate=self.sample_rate,
                    audio_duration_seconds=duration,
                    generation_time_seconds=gen_time,
                    rtf=rtf,
                )
            finally:
                try:
                    Path(ref_path).unlink(missing_ok=True)
                except Exception:
                    pass

    def _materialize_reference_wav(self, audio_bytes: bytes) -> str:
        ref_dir = Path(os.environ.get("F5_TMPDIR", "/tmp/f5-tts-refs"))
        ref_dir.mkdir(parents=True, exist_ok=True)
        ref_path = ref_dir / f"ref-{int(time.time() * 1000)}-{os.getpid()}.wav"
        ref_path.write_bytes(audio_bytes)
        return str(ref_path)