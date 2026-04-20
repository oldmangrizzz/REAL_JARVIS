using UnityEngine;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine.SceneManagement;
using System.IO;

// Headless WebGL build entry. Invoke with:
//   Unity -batchmode -nographics -quit -projectPath <proj> -executeMethod JarvisBuild.BuildWebGL -buildTarget WebGL
public static class JarvisBuild
{
    public static void BuildWebGL()
    {
        string scenePath = "Assets/Scenes/Workshop.unity";
        EnsureScene(scenePath);

        EditorUserBuildSettings.selectedBuildTargetGroup = BuildTargetGroup.WebGL;
        PlayerSettings.SetScriptingBackend(BuildTargetGroup.WebGL, ScriptingImplementation.IL2CPP);
        PlayerSettings.WebGL.compressionFormat = WebGLCompressionFormat.Gzip;
        PlayerSettings.WebGL.decompressionFallback = true;
        PlayerSettings.WebGL.linkerTarget = WebGLLinkerTarget.Wasm;
        PlayerSettings.SetIl2CppCodeGeneration(
            UnityEditor.Build.NamedBuildTarget.WebGL,
            UnityEditor.Build.Il2CppCodeGeneration.OptimizeSize);
        PlayerSettings.companyName = "GrizzlyMedicine Research Institute";
        PlayerSettings.productName  = "jarvis-workshop";

        // Output dir: $JARVIS_BUILD_OUT, or -buildOutput <path>, else ../pwa-Build next to project.
        string outDir = System.Environment.GetEnvironmentVariable("JARVIS_BUILD_OUT");
        if (string.IsNullOrEmpty(outDir)) {
            var args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == "-buildOutput") { outDir = args[i + 1]; break; }
        }
        if (string.IsNullOrEmpty(outDir))
            outDir = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "..", "unity-build"));
        if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir);

        var opts = new BuildPlayerOptions {
            scenes = new[] { scenePath },
            locationPathName = outDir,
            target = BuildTarget.WebGL,
            options = BuildOptions.None
        };
        var report = BuildPipeline.BuildPlayer(opts);
        Debug.Log($"[JarvisBuild] WebGL build → {outDir} :: result={report.summary.result} size={report.summary.totalSize}");
        EditorApplication.Exit(report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded ? 0 : 1);
    }

    static void EnsureScene(string path)
    {
        var dir = Path.GetDirectoryName(path);
        if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

        if (File.Exists(path)) {
            EditorSceneManager.OpenScene(path, OpenSceneMode.Single);
            return;
        }

        var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);

        // Bridge GameObject — name must literally be "JarvisBridge" (PWA→Unity SendMessage target).
        var bridge = new GameObject("JarvisBridge");
        bridge.AddComponent<JarvisBridge>();

        // One demo HoloPanel so the scene isn't blank on first load.
        var panel = GameObject.CreatePrimitive(PrimitiveType.Quad);
        panel.name = "HoloPanel-Main";
        panel.transform.position = new Vector3(0f, 1.6f, 2f);
        panel.AddComponent<HoloPanel>();

        EditorSceneManager.SaveScene(scene, path);
    }
}
