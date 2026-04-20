// SPDX-License-Identifier: Apache-2.0
// JarvisTunnelClient — thin Unity client that speaks the same TunnelFrame
// protocol as Jarvis/Shared/Sources/JarvisShared/TunnelModels.swift.
//
// Keep this file byte-compatible with the Swift reference. If the wire
// format changes, update BOTH sides in the same commit. The canon-gate CI
// enforces non-DOM UI; this file also honors that invariant (no WebView).

using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace Jarvis.Quest
{
    /// <summary>
    /// Minimal Jarvis host tunnel client. Registers as either
    /// <c>voice-operator</c> (requires green voice-approval gate) or
    /// <c>mobile-cockpit</c> (SPEC-007). Polls the cockpit snapshot at
    /// <c>pollIntervalSeconds</c> and fires <see cref="OnSnapshot"/>.
    /// </summary>
    public class JarvisTunnelClient : MonoBehaviour
    {
        [Header("Host Tunnel")]
        [Tooltip("Base URL of the Jarvis host tunnel server (echo host).")]
        public string hostURL = "http://echo.local:19480";

        [Tooltip("Shared secret from Jarvis/App/main.swift start-host-tunnel [secret]")]
        public string sharedSecret = "";

        [Tooltip("SPEC-007 role. Use 'mobile-cockpit' for read-only cockpit; " +
                 "'voice-operator' requires a GREEN voice-approval gate.")]
        public string role = "mobile-cockpit";

        [Header("Polling")]
        public float pollIntervalSeconds = 1.0f;

        [Serializable]
        public class CockpitSnapshot
        {
            public string status;
            public string voiceGateState;
            public string activeHUD;
            public long generatedAtEpochMs;
        }

        public event Action<CockpitSnapshot> OnSnapshot;
        public event Action<string> OnError;

        private bool _running;

        private void Start()
        {
            _running = true;
            StartCoroutine(PollLoop());
        }

        private void OnDisable()
        {
            _running = false;
        }

        private IEnumerator PollLoop()
        {
            while (_running)
            {
                yield return FetchSnapshot();
                yield return new WaitForSeconds(pollIntervalSeconds);
            }
        }

        private IEnumerator FetchSnapshot()
        {
            string url = $"{hostURL}/snapshot?role={UnityWebRequest.EscapeURL(role)}";
            using UnityWebRequest req = UnityWebRequest.Get(url);
            req.SetRequestHeader("Authorization", $"Bearer {sharedSecret}");
            req.SetRequestHeader("X-Jarvis-Client", "quest-cockpit/1.0");
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                OnError?.Invoke($"snapshot failed: {req.error}");
                yield break;
            }

            try
            {
                var snap = JsonUtility.FromJson<CockpitSnapshot>(req.downloadHandler.text);
                OnSnapshot?.Invoke(snap);
            }
            catch (Exception e)
            {
                OnError?.Invoke($"snapshot parse: {e.Message}");
            }
        }

        /// <summary>
        /// Compute a hex-encoded HMAC-SHA256 over <paramref name="payload"/>
        /// with <see cref="sharedSecret"/>. Matches TunnelCrypto.swift's
        /// <c>signFrame</c>.
        /// </summary>
        public string SignFrame(string payload)
        {
            using var hmac = new System.Security.Cryptography.HMACSHA256(
                Encoding.UTF8.GetBytes(sharedSecret));
            byte[] mac = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
            var sb = new StringBuilder(mac.Length * 2);
            foreach (byte b in mac) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }
    }
}
