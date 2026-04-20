"use strict";
/*
 * Jarvis Voice — Obsidian plugin.
 *
 * Reads the active note (or selection) aloud through the Jarvis-ratified
 * voice pipeline running on the Mac host. This plugin does NOT synthesize
 * locally — it POSTs plain text to the host's /speak endpoint and plays
 * the returned WAV. The host enforces the VoiceApprovalGate (SOUL_ANCHOR).
 *
 * Start the bridge on the Mac: `Jarvis start-voice-bridge`
 * Configure the plugin with the printed bearer token and host URL
 * (default http://jarvis.local:8787 or the Mac's LAN IP).
 *
 * No DOM rendering tricks, no speech synthesis spoofing. Just bytes on
 * the wire and a native <audio> playback.
 */

const { Plugin, PluginSettingTab, Setting, Notice, MarkdownView } = require("obsidian");

const DEFAULT_SETTINGS = {
    hostURL: "http://jarvis.local:8787",
    bearerToken: "",
    chunkSize: 1200
};

class JarvisVoicePlugin extends Plugin {
    async onload() {
        await this.loadSettings();
        this.currentAudio = null;

        this.addRibbonIcon("audio-file", "Jarvis: speak active note", () => this.speakActiveNote());

        this.addCommand({
            id: "speak-active-note",
            name: "Speak active note",
            callback: () => this.speakActiveNote()
        });

        this.addCommand({
            id: "speak-selection",
            name: "Speak selection",
            editorCallback: (editor) => {
                const sel = editor.getSelection();
                if (!sel || !sel.trim()) {
                    new Notice("Jarvis voice: no selection.");
                    return;
                }
                this.speak(sel);
            }
        });

        this.addCommand({
            id: "stop-playback",
            name: "Stop playback",
            callback: () => this.stop()
        });

        this.addSettingTab(new JarvisVoiceSettingTab(this.app, this));
    }

    onunload() {
        this.stop();
    }

    async loadSettings() {
        this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
    }

    async saveSettings() {
        await this.saveData(this.settings);
    }

    async speakActiveNote() {
        const view = this.app.workspace.getActiveViewOfType(MarkdownView);
        if (!view) {
            new Notice("Jarvis voice: open a markdown note first.");
            return;
        }
        const text = view.editor.getValue();
        if (!text || !text.trim()) {
            new Notice("Jarvis voice: note is empty.");
            return;
        }
        await this.speak(this.stripMarkdown(text));
    }

    stripMarkdown(raw) {
        return raw
            .replace(/```[\s\S]*?```/g, " ")
            .replace(/`([^`]*)`/g, "$1")
            .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
            .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
            .replace(/^#{1,6}\s+/gm, "")
            .replace(/^>\s?/gm, "")
            .replace(/[*_~]/g, "")
            .replace(/\s+\n/g, "\n")
            .replace(/\n{3,}/g, "\n\n")
            .trim();
    }

    chunkText(text, size) {
        if (text.length <= size) return [text];
        const chunks = [];
        const sentences = text.split(/(?<=[.!?])\s+/);
        let current = "";
        for (const s of sentences) {
            if ((current + " " + s).length > size && current.length > 0) {
                chunks.push(current.trim());
                current = s;
            } else {
                current = current ? current + " " + s : s;
            }
        }
        if (current.trim()) chunks.push(current.trim());
        return chunks;
    }

    async speak(text) {
        this.stop();
        const { hostURL, bearerToken, chunkSize } = this.settings;
        if (!hostURL || !bearerToken) {
            new Notice("Jarvis voice: configure host URL + bearer token in settings.");
            return;
        }
        const chunks = this.chunkText(text, Math.max(400, chunkSize || 1200));
        new Notice(`Jarvis voice: speaking ${chunks.length} chunk(s).`);
        this.stopRequested = false;
        for (let i = 0; i < chunks.length; i++) {
            if (this.stopRequested) break;
            try {
                const wav = await this.fetchWav(hostURL, bearerToken, chunks[i]);
                if (this.stopRequested) break;
                await this.playWav(wav);
            } catch (err) {
                new Notice(`Jarvis voice: ${err.message || err}`);
                return;
            }
        }
    }

    async fetchWav(hostURL, token, text) {
        const url = hostURL.replace(/\/+$/, "") + "/speak";
        const res = await fetch(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer " + token
            },
            body: JSON.stringify({ text })
        });
        if (!res.ok) {
            const body = await res.text().catch(() => "");
            throw new Error(`bridge ${res.status}: ${body || res.statusText}`);
        }
        return await res.blob();
    }

    playWav(blob) {
        return new Promise((resolve, reject) => {
            const url = URL.createObjectURL(blob);
            const audio = new Audio(url);
            this.currentAudio = audio;
            audio.onended = () => { URL.revokeObjectURL(url); resolve(); };
            audio.onerror = () => { URL.revokeObjectURL(url); reject(new Error("audio playback error")); };
            audio.play().catch(reject);
        });
    }

    stop() {
        this.stopRequested = true;
        if (this.currentAudio) {
            try { this.currentAudio.pause(); } catch (_) {}
            this.currentAudio = null;
        }
    }
}

class JarvisVoiceSettingTab extends PluginSettingTab {
    constructor(app, plugin) { super(app, plugin); this.plugin = plugin; }
    display() {
        const { containerEl } = this;
        containerEl.empty();
        containerEl.createEl("h2", { text: "Jarvis Voice" });

        new Setting(containerEl)
            .setName("Host URL")
            .setDesc("Jarvis voice bridge base URL (e.g. http://jarvis.local:8787 or http://192.168.x.x:8787)")
            .addText(t => t
                .setPlaceholder("http://jarvis.local:8787")
                .setValue(this.plugin.settings.hostURL)
                .onChange(async v => { this.plugin.settings.hostURL = v.trim(); await this.plugin.saveSettings(); }));

        new Setting(containerEl)
            .setName("Bearer token")
            .setDesc("Shared secret printed by `Jarvis start-voice-bridge` (or set JARVIS_VOICE_BRIDGE_SECRET).")
            .addText(t => t
                .setPlaceholder("hex token")
                .setValue(this.plugin.settings.bearerToken)
                .onChange(async v => { this.plugin.settings.bearerToken = v.trim(); await this.plugin.saveSettings(); }));

        new Setting(containerEl)
            .setName("Chunk size")
            .setDesc("Approximate max characters per TTS request. Long notes are split at sentence boundaries.")
            .addText(t => t
                .setPlaceholder("1200")
                .setValue(String(this.plugin.settings.chunkSize))
                .onChange(async v => { this.plugin.settings.chunkSize = parseInt(v, 10) || 1200; await this.plugin.saveSettings(); }));

        new Setting(containerEl)
            .setName("Test connection")
            .addButton(b => b.setButtonText("Ping /health").onClick(async () => {
                try {
                    const url = this.plugin.settings.hostURL.replace(/\/+$/, "") + "/health";
                    const res = await fetch(url);
                    new Notice(res.ok ? "Jarvis bridge: OK" : `Jarvis bridge: ${res.status}`);
                } catch (e) {
                    new Notice("Jarvis bridge unreachable: " + (e.message || e));
                }
            }));
    }
}

module.exports = JarvisVoicePlugin;
