FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

# Base dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    python3.10-venv \
    git \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install service-specific Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Clone and install F5‑TTS from upstream
RUN git clone https://github.com/microsoft/F5-TTS.git /opt/f5-tts && \
    pip install --no-cache-dir -e /opt/f5-tts

# Copy application code
COPY . .

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]