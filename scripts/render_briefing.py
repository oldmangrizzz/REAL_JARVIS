#!/usr/bin/env python3
"""Re-render MP3 briefing by POSTing each chunk to vibevoice and concatenating.

Requires a local tunnel to the vibevoice VM at localhost:8000 and the bearer
token. Reads the bearer from $VIBEVOICE_BEARER_FILE (default /tmp/vibevoice.bearer)
or $VIBEVOICE_BEARER env var. Do NOT commit bearer files.
"""
import glob, os, sys, subprocess, tempfile, urllib.request, json, time

bearer_env = os.environ.get("VIBEVOICE_BEARER")
bearer_file = os.environ.get("VIBEVOICE_BEARER_FILE", "/tmp/vibevoice.bearer")
if bearer_env:
    BEARER = bearer_env.strip()
elif os.path.exists(bearer_file):
    BEARER = open(bearer_file).read().strip()
else:
    sys.exit(f"no bearer: set VIBEVOICE_BEARER or populate {bearer_file}")
URL = os.environ.get("VIBEVOICE_URL", "http://localhost:8000/v1/audio/speech")
CHUNK_DIR = os.environ.get("CHUNK_DIR", "/Users/grizzmed/REAL_JARVIS/exports/.jarvis_report_chunks")
OUT_MP3 = os.environ.get("OUT_MP3", "/Users/grizzmed/REAL_JARVIS/JARVIS_INTELLIGENCE_BRIEF.mp3")

chunks = sorted(glob.glob(f"{CHUNK_DIR}/chunk-*.txt"))
print(f"[render] {len(chunks)} chunks", flush=True)
workdir = tempfile.mkdtemp(prefix="jarvisbrief_")
wavs = []
for i, path in enumerate(chunks, 1):
    text = open(path).read().strip()
    if not text: continue
    print(f"[render] chunk {i}/{len(chunks)}  text={len(text)}b", flush=True)
    body = json.dumps({"input": text, "voice": "ref0299", "response_format": "wav"}).encode()
    req = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {BEARER}",
    }, method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            data = r.read()
    except Exception as e:
        print(f"[render] ERR chunk {i}: {e}", flush=True)
        sys.exit(2)
    wav_path = os.path.join(workdir, f"chunk-{i:02d}.wav")
    with open(wav_path, "wb") as f: f.write(data)
    dt = time.time() - t0
    print(f"[render]   ok size={len(data)}  {dt:.1f}s", flush=True)
    wavs.append(wav_path)

# Concatenate via ffmpeg (re-encode to 24kHz mono for safety)
listfile = os.path.join(workdir, "list.txt")
with open(listfile, "w") as f:
    for w in wavs: f.write(f"file '{w}'\n")
print(f"[render] concat -> {OUT_MP3}", flush=True)
subprocess.run(["ffmpeg","-y","-f","concat","-safe","0","-i",listfile,
                "-ar","24000","-ac","1","-b:a","160k", OUT_MP3],
               check=True, stderr=subprocess.DEVNULL)
out = subprocess.run(["ffprobe","-v","error","-show_entries","format=duration,size",
                      "-of","default=noprint_wrappers=1",OUT_MP3],
                     capture_output=True, text=True).stdout
print(f"[render] DONE\n{out}")
