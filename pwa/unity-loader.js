// unity-loader.js — boots the Unity WebGL workshop inside the PWA.
// Gracefully falls back to the legacy DOM cockpit if the Unity Build/
// artifacts aren't present yet (expected until Phase 1/3 lands).

(function () {
  const BUILD_ROOT = 'Build';
  const BUILD_NAME = 'jarvis-workshop';
  const CANVAS_ID = 'unity-canvas';
  const PROGRESS_ID = 'unity-progress';
  const FALLBACK_ID = 'dom-cockpit';
  const XR_SHELL_ID = 'xr-shell';

  async function buildExists() {
    try {
      const r = await fetch(`${BUILD_ROOT}/${BUILD_NAME}.loader.js`, { method: 'HEAD' });
      return r.ok;
    } catch (_) {
      return false;
    }
  }

  function showFallback(reason) {
    console.warn('[jarvis/xr] falling back to DOM cockpit:', reason);
    const xr = document.getElementById(XR_SHELL_ID);
    const dom = document.getElementById(FALLBACK_ID);
    if (xr) xr.style.display = 'none';
    if (dom) dom.style.display = '';
  }

  function forwardToUnity(instance) {
    window.JarvisXR = Object.freeze({
      send(channel, payload) {
        try {
          instance.SendMessage('JarvisBridge', channel,
            typeof payload === 'string' ? payload : JSON.stringify(payload));
        } catch (e) { console.warn('[jarvis/xr] SendMessage failed', e); }
      },
      instance
    });
    document.addEventListener('jarvis:voice-state',   (e) => window.JarvisXR.send('OnVoiceState',   e.detail));
    document.addEventListener('jarvis:convex-snapshot', (e) => window.JarvisXR.send('OnConvexSnap',  e.detail));
    document.addEventListener('jarvis:mesh-heartbeat', (e) => window.JarvisXR.send('OnMeshHeartbeat', e.detail));
  }

  // Called from C# via Application.ExternalCall / [DllImport]
  window.jarvisFromUnity = function (channel, payloadJson) {
    let detail = payloadJson;
    try { detail = JSON.parse(payloadJson); } catch (_) {}
    document.dispatchEvent(new CustomEvent(`jarvis:unity:${channel}`, { detail }));
  };

  async function boot() {
    if (!(await buildExists())) {
      showFallback('Unity Build/ artifacts not present (expected pre-Phase-3).');
      return;
    }
    const canvas = document.getElementById(CANVAS_ID);
    const progress = document.getElementById(PROGRESS_ID);
    const config = {
      dataUrl: `${BUILD_ROOT}/${BUILD_NAME}.data.unityweb`,
      frameworkUrl: `${BUILD_ROOT}/${BUILD_NAME}.framework.js.unityweb`,
      codeUrl: `${BUILD_ROOT}/${BUILD_NAME}.wasm.unityweb`,
      streamingAssetsUrl: 'StreamingAssets',
      companyName: 'GMRI',
      productName: 'JARVIS Workshop',
      productVersion: '0.1.0',
    };
    const script = document.createElement('script');
    script.src = `${BUILD_ROOT}/${BUILD_NAME}.loader.js`;
    script.onload = () => {
      // eslint-disable-next-line no-undef
      createUnityInstance(canvas, config, (p) => {
        if (progress) progress.style.width = `${Math.round(p * 100)}%`;
      }).then((instance) => {
        if (progress) progress.parentElement.style.display = 'none';
        forwardToUnity(instance);
      }).catch((err) => showFallback(`createUnityInstance: ${err}`));
    };
    script.onerror = () => showFallback('loader.js failed to load');
    document.body.appendChild(script);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
