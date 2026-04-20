using UnityEngine;

// JarvisBridge — single GameObject sink for messages from the PWA shell.
// The PWA's unity-loader.js calls UnityInstance.SendMessage("JarvisBridge", channel, json).
// Unity emits back to JS via Application.ExternalCall("jarvisFromUnity", channel, json).
public class JarvisBridge : MonoBehaviour
{
    [System.Serializable] public class VoiceState   { public bool approved; public string fingerprint; public float confidence; }
    [System.Serializable] public class ConvexSnap   { public string payload; public long ts; }
    [System.Serializable] public class MeshBeat     { public string node; public string status; public long ts; }

    public static JarvisBridge I { get; private set; }
    public VoiceState  voice = new VoiceState();
    public ConvexSnap  convex = new ConvexSnap();
    public MeshBeat    mesh = new MeshBeat();

    void Awake() { I = this; DontDestroyOnLoad(gameObject); }

    void Start()
    {
        EmitToJs("workshop-ready", "{\"version\":\"0.1.0\"}");
    }

    // --- called by PWA ---
    public void OnVoiceState(string json)    { JsonUtility.FromJsonOverwrite(json, voice);  }
    public void OnConvexSnap(string json)    { JsonUtility.FromJsonOverwrite(json, convex); }
    public void OnMeshHeartbeat(string json) { JsonUtility.FromJsonOverwrite(json, mesh);   }

    // --- Unity → PWA ---
    public static void EmitToJs(string channel, string payloadJson)
    {
#if UNITY_WEBGL && !UNITY_EDITOR
        Application.ExternalCall("jarvisFromUnity", channel, payloadJson);
#else
        Debug.Log($"[JarvisBridge→JS] {channel}: {payloadJson}");
#endif
    }
}
