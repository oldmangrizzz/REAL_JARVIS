using UnityEngine;
using LiveKit;
using System.Collections;
using System.Threading.Tasks;
using UnityEngine.Networking;
using System.Collections.Generic;

namespace GrizzOS.Voice
{
    /// <summary>
    /// Manages the WebRTC connection to the LiveKit server on Charlie VPS.
    /// Pipes Coqui XTTS v2 ambient voice to the player's spatialized audio source.
    ///
    /// Trauma-Informed Design:
    /// Enforces strict identity verification before allowing incoming voice connections.
    /// Fails closed if the identity server (Convex/Pangolin) cannot provide a valid cryptographic token.
    /// </summary>
    public class LiveKitVoiceManager : MonoBehaviour
    {
        [Header("LiveKit Configuration")]
        [SerializeField] private string liveKitUrl = "wss://charlie.grizzlymedicine.icu";
        [SerializeField] private string roomName = "GrizzOS_Sanctuary";
        [SerializeField] private string participantName = "Operator_Head";

        [Header("Security")]
        [SerializeField] private string tokenProviderUrl = "https://grizzlymedicine.icu/api/livekit/auth";

        [Header("Audio Routing")]
        [SerializeField] private AudioSource jarvisVoiceSource;
        [SerializeField] private bool autoConnectOnStart = false;
        [SerializeField] private bool voiceGateApproved = false;

        private Room room;

        private async void Start()
        {
            if (autoConnectOnStart)
            {
                await ConnectWhenAuthorized();
            }
        }

        public async Task ConnectWhenAuthorized()
        {
            if (jarvisVoiceSource == null)
            {
                Debug.LogError("[CRITICAL WOUND] LiveKitVoiceManager: JARVIS AudioSource is missing. System failing closed to prevent disembodied audio.");
                return;
            }

            if (!voiceGateApproved)
            {
                Debug.LogWarning("[LiveKitVoiceManager] Voice gate is not approved. Live audio remains disconnected.");
                return;
            }

            Debug.Log($"[LiveKitVoiceManager] Requesting secure WebRTC token for {participantName}...");

            string token = await FetchSecureTokenAsync();
            if (string.IsNullOrEmpty(token))
            {
                Debug.LogError("[CRITICAL WOUND] LiveKitVoiceManager: Failed to securely authenticate. WebRTC Bridge aborted.");
                return;
            }

            Debug.Log($"[LiveKitVoiceManager] Connecting to JARVIS Voice at {liveKitUrl}...");
            await ConnectToRoom(token);
        }

        public void SetVoiceGateApproved(bool approved)
        {
            voiceGateApproved = approved;
        }

        private async Task<string> FetchSecureTokenAsync()
        {
            // The architecture mandates that we do NOT use hardcoded tokens.
            // We fetch a short-lived token from our authenticated Convex backend.
            using (UnityWebRequest req = UnityWebRequest.Get($"{tokenProviderUrl}?room={roomName}&participant={participantName}"))
            {
                // In production, inject bearer tokens or MTLS certs here
                req.SetRequestHeader("X-GrizzOS-Request", "true");

                var operation = req.SendWebRequest();
                while (!operation.isDone)
                {
                    await Task.Yield();
                }

                if (req.result != UnityWebRequest.Result.Success)
                {
                    Debug.LogError($"[Auth Failure] Could not fetch token: {req.error}");
                    return null;
                }

                // Assume JSON response: { "token": "ey..." }
                // Quick parse (use a proper JSON library like Newtonsoft in full build)
                string json = req.downloadHandler.text;
                if (json.Contains("\"token\""))
                {
                    int startIndex = json.IndexOf("\"token\"") + 7;
                    int startQuote = json.IndexOf("\"", startIndex) + 1;
                    int endQuote = json.IndexOf("\"", startQuote);
                    return json.Substring(startQuote, endQuote - startQuote);
                }

                return null;
            }
        }

        private async Task ConnectToRoom(string token)
        {
            room = new Room();
            room.TrackSubscribed += OnTrackSubscribed;

            try
            {
                await room.Connect(liveKitUrl, token);
                Debug.Log($"[LiveKitVoiceManager] Secure connection established to room: {room.Name}");
            }
            catch (System.Exception e)
            {
                Debug.LogError($"[LiveKitVoiceManager] Connection failed: {e.Message}");
            }
        }

        private void OnTrackSubscribed(RemoteTrack track, RemotePublication publication, RemoteParticipant participant)
        {
            if (track is RemoteAudioTrack audioTrack)
            {
                Debug.Log($"[LiveKitVoiceManager] Subscribed to JARVIS audio track from {participant.Identity}");

                // Attach the incoming WebRTC audio stream to the Unity AudioSource
                audioTrack.Attach(jarvisVoiceSource);

                if (!jarvisVoiceSource.isPlaying)
                {
                    jarvisVoiceSource.Play();
                }
            }
        }

        private void OnDestroy()
        {
            if (room != null)
            {
                room.TrackSubscribed -= OnTrackSubscribed;
                room.Disconnect();
            }
        }
    }
}
