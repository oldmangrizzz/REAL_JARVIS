"""
F5‑TTS singleton wrapper.

Loads the F5‑TTS model once on first use, keeps it resident in GPU/CPU
memory and provides a thread‑safe ``synthesize`` method that returns
raw WAV bytes together with useful metadata.

The wrapper also tracks the timestamp of the last synthesis call so
the surrounding FastAPI application can shut down the model after a
period of inactivity (idle‑shutdown).
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
    """Result of a single synthesis operation."""

    wav_bytes: bytes
    sample_rate: int
    audio_duration_seconds: float
    generation_time_seconds: float
    rtf: float


class F5Synthesizer:
    """
    Thread‑safe singleton that lazily loads the F5‑TTS model.

    The model stays loaded until :meth:`maybe_unload` decides to free the
    resources after a configurable idle period.
    """

    _instance_lock = threading.Lock()
    _instance: "F5Synthesizer | None" = None

    @classmethod
    def shared(cls) -> "F5Synthesizer":
        """Return the global singleton, creating it on first call."""
        with cls._instance_lock:
            if cls._instance is None:
                cls._instance = cls()
            return cls._instance

    def __init__(self) -> None:
        # Configuration ---------------------------------------------------------
        self.model_path = os.environ.get(
            "F5_MODEL_PATH", "SWivid/F5-TTS_v1_Base"
        )
        # Device selection: explicit env var > CUDA > MPS > CPU
        self.device = os.environ.get("F5_DEVICE") or (
            "cuda"
            if torch.cuda.is_available()
            else "mps"
            if torch.backends.mps.is_available()
            else "cpu"
        )
        self.sample_rate = 24_000

        # Runtime state ---------------------------------------------------------
        self._render_lock = threading.Lock()
        self._load_lock = threading.Lock()
        self._loaded = False
        self.last_use_ts = time.time()
        self.model = None
        self.processor = None
        self.vocoder = None

    # --------------------------------------------------------------------- #
    # Loading / Unloading
    # --------------------------------------------------------------------- #

    def ensure_loaded(self) -> None:
        """Load the model lazily; safe to call from multiple threads."""
        if self._loaded:
            return
        with self._load_lock:
            if self._loaded:  # double‑checked locking
                return
            self._load()
            self._loaded = True

    def _load(self) -> None:
        """Perform the actual heavy‑weight import and model construction."""
        try:
            from f5_tts import F5TTS, F5Processor
            from f5_tts.utils import load_vocoder
        except ImportError as exc:
            raise RuntimeError(
                "F5‑TTS not installed. Run "
                "'pip install git+https://github.com/SWivid/f5-tts'"
            ) from exc

        # Use bfloat16 on CUDA for memory efficiency; otherwise float32.
        load_dtype = torch.bfloat16 if self.device == "cuda" else torch.float32

        print(
            f"[F5Synthesizer] Loading model from {self.model_path} on {self.device}...",
            flush=True,
        )

        try:
            self.processor = F5Processor.from_pretrained(self.model_path)
            self.model = F5TTS.from_pretrained(
                self.model_path, torch_dtype=load_dtype
            )
            self.vocoder = load_vocoder(self.model_path, device=self.device)

            # Move to the selected device (MPS needs explicit handling)
            if self.device == "mps":
                self.model.to("mps")
                self.vocoder.to("mps")
            elif self.device != "cpu":
                self.model.to(self.device)
                self.vocoder.to(self.device)

            self.model.eval()
        except Exception as exc:
            traceback.print_exc()
            raise RuntimeError(
                f"Failed to load F5‑TTS model from {self.model_path}"
            ) from exc

    def unload(self) -> None:
        """Free model, processor and vocoder resources."""
        with self._load_lock:
            if not self._loaded:
                return
            # Explicitly delete to break reference cycles
            del self.model
            del self.processor
            del self.vocoder
            self.model = None
            self.processor = None
            self.vocoder = None
            self._loaded = False
            # Release GPU memory if applicable
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            print("[F5Synthesizer] Model unloaded due to inactivity.", flush=True)

    def idle_seconds(self) -> float:
        """Return how many seconds have passed since the last synthesis."""
        return time.time() - self.last_use_ts

    def maybe_unload(self, max_idle_seconds: float = 300.0) -> bool:
        """
        Unload the model if it has been idle longer than *max_idle_seconds*.

        Returns ``True`` if the model was unloaded, ``False`` otherwise.
        """
        if self._loaded and self.idle_seconds() > max_idle_seconds:
            self.unload()
            return True
        return False

    # --------------------------------------------------------------------- #
    # Synthesis
    # --------------------------------------------------------------------- #

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
        """
        Generate speech from *text* conditioned on a reference audio clip.

        Parameters
        ----------
        text: str
            The target utterance to synthesize.
        reference_audio_bytes: bytes
            WAV‑encoded reference audio (used for voice style).
        reference_text: str
            Transcription of the reference audio.
        cfg_scale: float, optional
            Classifier‑free guidance scale (default 2.0).
        nfe_steps: int, optional
            Number of diffusion steps (default 32).
        seed: int | None, optional
            Random seed for reproducibility.
        speaker_label: str, optional
            Currently unused – kept for API compatibility.

        Returns
        -------
        SynthesisResult
            Container with the generated WAV bytes and timing metadata.
        """
        self.ensure_loaded()

        with self._render_lock:
            if seed is not None:
                torch.manual_seed(seed)
                if torch.cuda.is_available():
                    torch.cuda.manual_seed_all(seed)

            ref_path = self._materialize_reference_wav(reference_audio_bytes)

            try:
                t0 = time.time()

                # -----------------------------------------------------------------
                # 1️⃣  Prepare inputs for the model
                # -----------------------------------------------------------------
                inputs = self.processor(
                    text=text,
                    reference_audio_path=ref_path,
                    reference_transcription=reference_text,
                    return_tensors="pt",
                )

                # Move tensors to the selected device
                target_device = self.device if self.device != "cpu" else "cpu"
                for key, value in inputs.items():
                    if torch.is_tensor(value):
                        inputs[key] = value.to(target_device)

                # -----------------------------------------------------------------
                # 2️⃣  Generate mel‑spectrogram
                # -----------------------------------------------------------------
                with torch.no_grad():
                    mel_outputs = self.model.generate(
                        **inputs,
                        cfg_scale=cfg_scale,
                        nfe_steps=nfe_steps,
                    )

                # -----------------------------------------------------------------
                # 3️⃣  Vocoder → waveform
                # -----------------------------------------------------------------
                with torch.no_grad():
                    audio = self.vocoder(mel_outputs).squeeze()
                    audio = audio.cpu().numpy()

                gen_time = time.time() - t0

                # -----------------------------------------------------------------
                # 4️⃣  Post‑process and encode as WAV
                # -----------------------------------------------------------------
                audio = np.clip(audio, -1.0, 1.0)

                buf = io.BytesIO()
                sf.write(
                    buf,
                    audio,
                    self.sample_rate,
                    format="WAV",
                    subtype="PCM_16",
                )
                wav_bytes = buf.getvalue()

                duration = len(audio) / float(self.sample_rate)
                rtf = gen_time / duration if duration > 0 else float("inf")

                # Update idle timer
                self.last_use_ts = time.time()

                return SynthesisResult(
                    wav_bytes=wav_bytes,
                    sample_rate=self.sample_rate,
                    audio_duration_seconds=duration,
                    generation_time_seconds=gen_time,
                    rtf=rtf,
                )
            finally:
                # Clean up the temporary reference file
                try:
                    Path(ref_path).unlink(missing_ok=True)
                except Exception:
                    pass

    # --------------------------------------------------------------------- #
    # Helpers
    # --------------------------------------------------------------------- #

    def _materialize_reference_wav(self, audio_bytes: bytes) -> str:
        """
        Write *audio_bytes* to a temporary file and return its path.

        The temporary directory can be overridden with the ``F5_TMPDIR``
        environment variable.
        """
        ref_dir = Path(os.environ.get("F5_TMPDIR", "/tmp/f5-tts-refs"))
        ref_dir.mkdir(parents=True, exist_ok=True)
        ref_path = ref_dir / f"ref-{int(time.time() * 1000)}-{os.getpid()}.wav"
        ref_path.write_bytes(audio_bytes)
        return str(ref_path)


__all__ = ["F5Synthesizer", "SynthesisResult"]