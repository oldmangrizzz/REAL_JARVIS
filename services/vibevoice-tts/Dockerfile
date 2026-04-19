# JARVIS VibeVoice TTS service — CUDA 12.1 / PyTorch 2.4 / T4-ready
# Build:   docker build -t jarvis-vibevoice-tts:latest .
# Run:     docker run --gpus all -e VIBEVOICE_BEARER=$TOKEN -p 8000:8000 jarvis-vibevoice-tts:latest

FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HOME=/models/.hf \
    TRANSFORMERS_CACHE=/models/.hf/transformers \
    VIBEVOICE_MODEL_PATH=vibevoice/VibeVoice-1.5B \
    VIBEVOICE_DEVICE=cuda \
    VIBEVOICE_IDLE_SECONDS=1800 \
    VIBEVOICE_PRELOAD=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 python3.10-dev python3-pip git ffmpeg libsndfile1 ca-certificates \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/python3.10 /usr/bin/python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python deps first (layer cache)
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip setuptools wheel \
    && pip install --extra-index-url https://download.pytorch.org/whl/cu121 -r /app/requirements.txt

# Community VibeVoice (the official MS repo no longer hosts the TTS code)
RUN pip install "git+https://github.com/vibevoice-community/VibeVoice.git@main"

# flash-attn is optional; falls back to sdpa in synthesizer.py if missing.
# Pinned wheel for torch 2.4 + cu121.
RUN pip install --no-build-isolation flash-attn==2.6.3 || echo "flash-attn install skipped; sdpa fallback active"

COPY app.py /app/app.py
COPY synthesizer.py /app/synthesizer.py

EXPOSE 8000

# Single worker — model is GPU-resident and not safe to fork.
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--timeout-keep-alive", "120"]
