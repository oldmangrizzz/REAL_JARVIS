"""
VibeVoice singleton wrapper. Loads model once on first use, holds it
in CUDA memory, exposes a single `synthesize()` call. Tracks last-use
timestamp so the FastAPI app can shut itself down on idle.
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

from vibevoice.modular.modeling_vibevoice_inference import (
    VibeVoiceForConditionalGenerationInference,
)
from vibevoice.processor.vibevoice_processor import VibeVoiceProcessor


@dataclass
class SynthesisResult:
    wav_bytes: bytes
    sample_rate: int
    audio_duration_seconds: float
    generation_time_seconds: float
    rtf: float


class VibeVoiceSynthesizer:
    """Thread-safe singleton. CUDA model stays resident."""

    _instance_lock = threading.Lock()
    _instance: "VibeVoiceSynthesizer | None" = None

    @classmethod
    def shared(cls) -> "VibeVoiceSynthesizer":
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def __init__(self) -> None:
        self.model_path = os.environ.get("VIBEVOICE_MODEL_PATH", "vibevoice/VibeVoice-1.5B")
        self.device = os.environ.get("VIBEVOICE_DEVICE") or (
            "cuda" if torch.cuda.is_available()
            else "mps" if torch.backends.mps.is_available()
            else "cpu"
        )
        self.sample_rate = 24_000
        self._render_lock = threading.Lock()
        self._loaded = False
        self.last_use_ts = time.time()
        self.model = None
        self.processor = None

    def ensure_loaded(self) -> None:
        if self._loaded:
            return
        with self._render_lock:
            if self._loaded:
                return
            self._load()
            self._loaded = True

    def _load(self) -> None:
        if self.device == "cuda":
            load_dtype = torch.bfloat16
            attn_impl = "flash_attention_2"
        elif self.device == "mps":
            load_dtype = torch.float32
            attn_impl = "sdpa"
        else:
            load_dtype = torch.float32
            attn_impl = "sdpa"

        self.processor = VibeVoiceProcessor.from_pretrained(self.model_path)
        try:
            self.model = VibeVoiceForConditionalGenerationInference.from_pretrained(
                self.model_path,
                torch_dtype=load_dtype,
                device_map=self.device if self.device in ("cuda", "cpu") else None,
                attn_implementation=attn_impl,
            )
        except Exception:
            traceback.print_exc()
            # flash-attn unavailable on this image — fall back to sdpa.
            self.model = VibeVoiceForConditionalGenerationInference.from_pretrained(
                self.model_path,
                torch_dtype=load_dtype,
                device_map=self.device if self.device in ("cuda", "cpu") else None,
                attn_implementation="sdpa",
            )
        if self.device == "mps":
            self.model.to("mps")
        self.model.eval()
        self.model.set_ddpm_inference_steps(num_steps=10)

    def synthesize(
        self,
        text: str,
        reference_audio_bytes: bytes,
        cfg_scale: float = 1.3,
        ddpm_steps: int = 10,
        seed: int | None = None,
        speaker_label: str = "Jarvis",
    ) -> SynthesisResult:
        self.ensure_loaded()

        with self._render_lock:
            if seed is not None:
                torch.manual_seed(seed)
                if torch.cuda.is_available():
                    torch.cuda.manual_seed_all(seed)

            self.model.set_ddpm_inference_steps(num_steps=ddpm_steps)

            ref_path = self._materialize_reference_wav(reference_audio_bytes)
            full_script = f"Speaker 1: {text.strip()}"

            try:
                inputs = self.processor(
                    text=[full_script],
                    voice_samples=[[ref_path]],
                    padding=True,
                    return_tensors="pt",
                    return_attention_mask=True,
                )
                target_device = self.device if self.device != "cpu" else "cpu"
                for k, v in inputs.items():
                    if torch.is_tensor(v):
                        inputs[k] = v.to(target_device)

                t0 = time.time()
                outputs = self.model.generate(
                    **inputs,
                    max_new_tokens=None,
                    cfg_scale=cfg_scale,
                    tokenizer=self.processor.tokenizer,
                    generation_config={"do_sample": False},
                    verbose=False,
                    is_prefill=True,
                )
                gen_time = time.time() - t0

                speech = outputs.speech_outputs[0]
                if speech is None:
                    raise RuntimeError("VibeVoice returned no audio output.")

                audio = speech.detach().to(torch.float32).cpu().numpy()
                if audio.ndim > 1:
                    audio = audio.squeeze()
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
        ref_dir = Path(os.environ.get("VIBEVOICE_TMPDIR", "/tmp/vibevoice-refs"))
        ref_dir.mkdir(parents=True, exist_ok=True)
        ref_path = ref_dir / f"ref-{int(time.time() * 1000)}-{os.getpid()}.wav"
        ref_path.write_bytes(audio_bytes)
        return str(ref_path)
