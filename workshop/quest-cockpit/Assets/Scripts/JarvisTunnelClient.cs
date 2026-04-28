// SPDX-License-Identifier: Apache-2.0
//
// Quest-side cockpit sync for Meta Quest 3.
//
// Apple phone/watch are the canonical mobile surfaces. Quest mirrors the same
// shared cockpit state and safety posture: visual cockpit first, no free-fire
// commands, Roger Roger/GhostLine control-plane only until the live media plane
// is explicitly wired.

using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace Jarvis.Quest
{
    public enum QuestConnectionState
    {
        disconnected,
        connecting,
        online,
        degraded,
        failed
    }

    public enum RogerRogerMode
    {
        sentinel,
        push_to_talk,
        full_duplex_live_speech
    }

    public enum GhostLineEndpoint
    {
        elehear_beyond,
        watch_speaker,
        watch_haptics_text,
        iphone_broker,
        ipad_veil,
        mac_veil,
        homepods,
        carplay,
        quest_cockpit,
        unknown
    }

    /// <summary>
    /// Mirrors the Apple TestFlight cockpit over Convex shared state.
    /// Commands remain restricted to Obsidian Command Bar and terminal.
    /// </summary>
    public sealed class JarvisTunnelClient : MonoBehaviour
    {
        [Header("Release Configuration")]
        [Tooltip("Convex deployment URL used by Apple mobile clients.")]
        public string convexURL = "https://enduring-starfish-794.convex.cloud";

        [Tooltip("Host address is displayed and validated for release parity. Quest does not open the encrypted TCP tunnel yet.")]
        public string hostAddress = "";

        [Tooltip("Host tunnel port. Apple TestFlight currently uses 9443.")]
        public ushort hostPort = 9443;

        [Tooltip("Shared host secret. Required for release builds; never commit it.")]
        public string sharedSecret = "";

        [Tooltip("Optional Convex bearer token, if the deployment requires one.")]
        public string convexAuthToken = "";

        [Header("Device Identity")]
        public string deviceName = "Quest 3 Cockpit";
        public string role = "quest";
        public string appVersion = "1.0";

        [Header("Polling")]
        public float pollIntervalSeconds = 1.0f;

        [Header("Roger Roger / GhostLine")]
        public RogerRogerMode rogerRogerMode = RogerRogerMode.sentinel;
        public GhostLineEndpoint preferredEndpoint = GhostLineEndpoint.quest_cockpit;

        public event Action<JarvisSharedState> OnSharedState;
        public event Action<QuestConnectionState, string> OnConnectionStateChanged;
        public event Action<string> OnError;

        private string _deviceID;
        private bool _running;
        private QuestConnectionState _connectionState = QuestConnectionState.disconnected;

        private void Awake()
        {
            _deviceID = PlayerPrefs.GetString("jarvis.quest.device-id", "");
            if (string.IsNullOrWhiteSpace(_deviceID))
            {
                _deviceID = Guid.NewGuid().ToString();
                PlayerPrefs.SetString("jarvis.quest.device-id", _deviceID);
                PlayerPrefs.Save();
            }
        }

        private void Start()
        {
            if (!ConfigurationIsSafe())
            {
                Publish(QuestConnectionState.failed, "Quest cockpit configuration is incomplete or unsafe for release.");
                return;
            }

            _running = true;
            StartCoroutine(StartAndPoll());
        }

        private void OnDisable()
        {
            _running = false;
            Publish(QuestConnectionState.disconnected, "Quest cockpit stopped.");
        }

        public void SetRogerRogerSentinel() => SetRogerRogerMode(RogerRogerMode.sentinel);
        public void SetRogerRogerPushToTalk() => SetRogerRogerMode(RogerRogerMode.push_to_talk);
        public void SetRogerRogerFullLiveSpeech() => SetRogerRogerMode(RogerRogerMode.full_duplex_live_speech);

        public void SetRogerRogerMode(RogerRogerMode mode)
        {
            rogerRogerMode = mode;
            preferredEndpoint = mode switch
            {
                RogerRogerMode.sentinel => GhostLineEndpoint.watch_haptics_text,
                RogerRogerMode.push_to_talk => GhostLineEndpoint.watch_speaker,
                RogerRogerMode.full_duplex_live_speech => GhostLineEndpoint.elehear_beyond,
                _ => GhostLineEndpoint.quest_cockpit
            };

            Publish(_connectionState, $"{DisplayName(mode)}: {WatchLine(mode)}");
        }

        public void PerformCommand(string ignoredAction)
        {
            Publish(_connectionState, "Command execution is restricted to the Obsidian Command Bar and terminal.");
        }

        private IEnumerator StartAndPoll()
        {
            Publish(QuestConnectionState.connecting, "Registering Quest cockpit with shared state.");
            yield return PostMutation("jarvis:registerMobileDevice", JsonUtility.ToJson(RegisterArgs.Create(_deviceID, deviceName, role, appVersion)));

            while (_running)
            {
                yield return FetchSharedState();
                yield return PostMutation("jarvis:recordMobileHeartbeat", JsonUtility.ToJson(HeartbeatArgs.Create(_deviceID, _connectionState.ToString())));
                yield return new WaitForSeconds(Mathf.Max(0.5f, pollIntervalSeconds));
            }
        }

        private IEnumerator FetchSharedState()
        {
            string args = JsonUtility.ToJson(LimitArgs.Create(8));
            using UnityWebRequest req = BuildConvexRequest("query", "jarvis:sharedMobileState", args);
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Publish(QuestConnectionState.degraded, $"shared state failed: {req.error}");
                OnError?.Invoke(req.error);
                yield break;
            }

            var envelope = JsonUtility.FromJson<SharedStateEnvelope>(req.downloadHandler.text);
            if (envelope == null || envelope.value == null)
            {
                Publish(QuestConnectionState.degraded, "Convex shared state response did not include a value payload.");
                OnError?.Invoke("Convex shared state response did not include a value payload.");
                yield break;
            }

            if (!string.IsNullOrWhiteSpace(envelope.errorMessage))
            {
                Publish(QuestConnectionState.degraded, envelope.errorMessage);
                OnError?.Invoke(envelope.errorMessage);
                yield break;
            }

            Publish(QuestConnectionState.online, "Quest cockpit shared state online.");
            OnSharedState?.Invoke(envelope.value);
        }

        private IEnumerator PostMutation(string path, string argsJson)
        {
            using UnityWebRequest req = BuildConvexRequest("mutation", path, argsJson);
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Publish(QuestConnectionState.degraded, $"{path} failed: {req.error}");
                OnError?.Invoke(req.error);
                yield break;
            }

            var envelope = JsonUtility.FromJson<BooleanEnvelope>(req.downloadHandler.text);
            if (envelope == null)
            {
                Publish(QuestConnectionState.degraded, $"{path} response was not a valid Convex envelope.");
                OnError?.Invoke($"{path} response was not a valid Convex envelope.");
                yield break;
            }

            if (!string.IsNullOrWhiteSpace(envelope.errorMessage))
            {
                Publish(QuestConnectionState.degraded, envelope.errorMessage);
                OnError?.Invoke(envelope.errorMessage);
            }
        }

        private UnityWebRequest BuildConvexRequest(string endpoint, string path, string argsJson)
        {
            string url = $"{convexURL.TrimEnd('/')}/api/{endpoint}";
            string body = $"{{\"path\":\"{JsonEscape(path)}\",\"args\":{argsJson}}}";
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(body);
            var req = new UnityWebRequest(url, "POST")
            {
                uploadHandler = new UploadHandlerRaw(bodyRaw),
                downloadHandler = new DownloadHandlerBuffer()
            };
            req.SetRequestHeader("Content-Type", "application/json");
            req.SetRequestHeader("X-Jarvis-Client", "quest-cockpit/1.0");
            if (!string.IsNullOrWhiteSpace(convexAuthToken))
            {
                req.SetRequestHeader("Authorization", $"Bearer {convexAuthToken}");
            }
            return req;
        }

        private bool ConfigurationIsSafe()
        {
#if UNITY_EDITOR || DEVELOPMENT_BUILD
            return !string.IsNullOrWhiteSpace(convexURL);
#else
            return !string.IsNullOrWhiteSpace(convexURL)
                && !string.IsNullOrWhiteSpace(hostAddress)
                && hostAddress != "127.0.0.1"
                && hostAddress != "localhost"
                && !hostAddress.StartsWith("$(", StringComparison.Ordinal)
                && hostPort > 0
                && !string.IsNullOrWhiteSpace(sharedSecret)
                && sharedSecret != "SET_VIA_BUILD_CONFIG"
                && sharedSecret != "$(JARVIS_SHARED_SECRET)";
#endif
        }

        private void Publish(QuestConnectionState state, string message)
        {
            _connectionState = state;
            OnConnectionStateChanged?.Invoke(state, message);
        }

        private static string JsonEscape(string value)
        {
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static string DisplayName(RogerRogerMode mode)
        {
            return mode switch
            {
                RogerRogerMode.sentinel => "Sentinel",
                RogerRogerMode.push_to_talk => "Push to Talk",
                RogerRogerMode.full_duplex_live_speech => "Full Live Speech",
                _ => mode.ToString()
            };
        }

        private static string WatchLine(RogerRogerMode mode)
        {
            return mode switch
            {
                RogerRogerMode.sentinel => "Listening quietly. Haptics + watch text.",
                RogerRogerMode.push_to_talk => "Hold to speak. Replies route by GhostLine.",
                RogerRogerMode.full_duplex_live_speech => "Live two-way audio channel.",
                _ => ""
            };
        }
    }

    [Serializable]
    public sealed class JarvisSharedState
    {
        public JarvisHostSnapshot snapshot;
        public JarvisThoughtSnapshot[] thoughts;
        public JarvisSignalSnapshot[] signals;
        public JarvisPushDirective[] pendingPushDirectives;
        public JarvisHomeKitBridgeStatus homeKitBridge;
        public JarvisObsidianVaultStatus obsidianVault;
        public JarvisNodeHeartbeat[] nodeRegistry;
        public JarvisGUIIntent[] guiIntents;
        public JarvisRustDeskNode[] rustDeskNodes;
    }

    [Serializable]
    public sealed class JarvisHostSnapshot
    {
        public string hostName;
        public string statusLine;
        public int indexedSkillCount;
        public int callableSkillCount;
        public int voiceSampleCount;
        public string tunnelState;
        public string activeWorkflow;
        public string lastMutation;
        public JarvisThoughtSnapshot[] recentThoughts;
        public JarvisSignalSnapshot[] recentSignals;
        public JarvisHomeKitBridgeStatus homeKitBridge;
        public JarvisObsidianVaultStatus obsidianVault;
        public JarvisNodeHeartbeat[] nodeRegistry;
        public JarvisGUIIntent[] guiIntents;
        public JarvisRustDeskNode[] rustDeskNodes;
        public JarvisVoiceGateSnapshot voiceGate;
        public JarvisSpatialHUDElement[] spatialHUD;
    }

    [Serializable]
    public sealed class JarvisVoiceGateSnapshot
    {
        public string state;
        public string stateName;
        public string composite;
        public string modelRepository;
        public string personaFramingVersion;
        public string approvedAtISO8601;
        public string operatorLabel;
        public string notes;
        public string lastSyncISO8601;
    }

    [Serializable]
    public sealed class JarvisSpatialHUDElement
    {
        public string id;
        public string kind;
        public string label;
        public string state;
        public string anchor;
        public string glyph;
        public string detail;
        public string lastUpdatedISO8601;
    }

    [Serializable]
    public sealed class JarvisThoughtSnapshot
    {
        public string id;
        public string sessionID;
        public string[] trace;
        public bool memoryPageFault;
        public string timestamp;
        public string sourceDeviceID;
    }

    [Serializable]
    public sealed class JarvisSignalSnapshot
    {
        public string id;
        public string nodeSource;
        public string nodeTarget;
        public int ternaryValue;
        public string agentID;
        public double pheromone;
        public string timestamp;
    }

    [Serializable]
    public sealed class JarvisHomeKitBridgeStatus
    {
        public string bridgeName;
        public string charlieAddress;
        public int homebridgePort;
        public bool reachable;
        public bool matterEnabled;
        public string voiceIntercomRoute;
        public string[] authorizedCommandSources;
        public string regulationVisibility;
        public string distressState;
        public string bridgeState;
        public JarvisHomeKitAccessoryStatus[] accessories;
        public string lastSync;
    }

    [Serializable]
    public sealed class JarvisHomeKitAccessoryStatus
    {
        public string id;
        public string name;
        public string kind;
        public string room;
        public string state;
        public string severity;
        public double value;
        public string lastUpdated;
    }

    [Serializable]
    public sealed class JarvisObsidianVaultStatus
    {
        public string databaseName;
        public string betaCouchEndpoint;
        public int docCount;
        public bool replicationConfigured;
        public bool replicationObserved;
        public bool reseedTriggered;
        public bool pluginListening;
        public string lastSync;
        public string statusLine;
    }

    [Serializable]
    public sealed class JarvisNodeHeartbeat
    {
        public string id;
        public string nodeName;
        public string address;
        public string source;
        public string tunnelState;
        public bool guiReachable;
        public string rustDeskID;
        public string lastSeen;
    }

    [Serializable]
    public sealed class JarvisGUIIntent
    {
        public string id;
        public string sourceNode;
        public string[] targetNodes;
        public string action;
        public string payloadJSON;
        public string queuedAt;
        public string status;
    }

    [Serializable]
    public sealed class JarvisRustDeskNode
    {
        public string id;
        public string nodeName;
        public string rustDeskID;
        public string address;
        public bool relayLocked;
        public string lastSeen;
        public string handoffURL;
        public string status;
    }

    [Serializable]
    public sealed class JarvisPushDirective
    {
        public string id;
        public string title;
        public string body;
        public string startupLine;
        public bool requiresSpeech;
        public string timestamp;
    }

    [Serializable]
    public sealed class SharedStateEnvelope
    {
        public JarvisSharedState value;
        public string errorMessage;

    }

    [Serializable]
    public sealed class BooleanEnvelope
    {
        public bool value;
        public string errorMessage;

    }

    [Serializable]
    public sealed class RegisterArgs
    {
        public string deviceId;
        public string deviceName;
        public string platform;
        public string role;
        public string appVersion;

        public static RegisterArgs Create(string deviceID, string deviceName, string role, string appVersion)
        {
            return new RegisterArgs
            {
                deviceId = deviceID,
                deviceName = deviceName,
                platform = "Quest 3",
                role = role,
                appVersion = appVersion
            };
        }
    }

    [Serializable]
    public sealed class HeartbeatArgs
    {
        public string deviceId;
        public string tunnelState;
        public string pushToken;

        public static HeartbeatArgs Create(string deviceID, string tunnelState)
        {
            return new HeartbeatArgs
            {
                deviceId = deviceID,
                tunnelState = tunnelState,
                pushToken = null
            };
        }
    }

    [Serializable]
    public sealed class LimitArgs
    {
        public int limit;

        public static LimitArgs Create(int limit)
        {
            return new LimitArgs { limit = limit };
        }
    }
}
