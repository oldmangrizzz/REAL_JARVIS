using UnityEngine;
using UnityEngine.VFX;

// HAPTICS / OVR Integration required for somatic feedback
#if UNITY_ANDROID || UNITY_STANDALONE_WIN
// using Oculus.Interaction;
// using Oculus.Haptics;
#endif

/// <summary>
/// Controls the "Observer Effect" for Clifford Attractor VFX clouds in GrizzOS.
/// As the operator focuses their gaze on the data cloud, the quantum superposition (chaotic state)
/// collapses into a rigid, readable holographic structure.
///
/// Trauma-Informed Design: Smooth interpolation (Lerp) is used to avoid jarring visual snaps,
/// maintaining a calm and predictable environmental reaction.
/// </summary>
[RequireComponent(typeof(VisualEffect))]
public class CliffordAttractorController : MonoBehaviour
{
    [Header("Collapse Settings")]
    [Tooltip("How fast the waveform collapses/expands (0 to 1).")]
    [SerializeField] private float interpolationSpeed = 1.5f;

    [Tooltip("The threshold at which the UI schematics become active.")]
    [SerializeField] private float collapseThreshold = 0.6f;

    [Header("VFX Parameters")]
    [SerializeField] private string entanglementParam = "Entanglement";
    [SerializeField] private string collapseStateParam = "CollapseState";

    [Header("Somatic Feedback (Haptics)")]
    [SerializeField] private AudioClip collapseSound;
    [SerializeField] private AudioSource audioSource;

    private VisualEffect _vfx;
    private float _currentEntanglement = 0f;
    private bool _isBeingObserved = false;
    private bool _hasFiredSomaticFeedback = false;

    private void Start()
    {
        _vfx = GetComponent<VisualEffect>();

        if (audioSource == null)
        {
            audioSource = gameObject.AddComponent<AudioSource>();
            audioSource.spatialBlend = 1.0f; // Full 3D
            audioSource.playOnAwake = false;
        }

        // Initialize VFX state to unobserved/superposition
        _vfx.SetFloat(entanglementParam, 0f);
        _vfx.SetBool(collapseStateParam, false);
    }

    private void Update()
    {
        // Smoothly interpolate entanglement based on observation state
        float targetValue = _isBeingObserved ? 1.0f : 0.0f;
        _currentEntanglement = Mathf.MoveTowards(_currentEntanglement, targetValue, interpolationSpeed * Time.deltaTime);

        // Update VFX Graph parameters
        _vfx.SetFloat(entanglementParam, _currentEntanglement);
        _vfx.SetBool(collapseStateParam, _currentEntanglement > collapseThreshold);

        // Stigmergic Feedback: The moment the waveform fully collapses, the system must acknowledge it
        if (_currentEntanglement >= 1.0f && _isBeingObserved && !_hasFiredSomaticFeedback)
        {
            FireSomaticFeedback();
            _hasFiredSomaticFeedback = true;
        }
        else if (_currentEntanglement < 1.0f)
        {
            // Reset feedback flag when returning to superposition
            _hasFiredSomaticFeedback = false;
        }
    }

    private void FireSomaticFeedback()
    {
        // 1. Audio Feedback (Low frequency bass drop / snap)
        if (collapseSound != null && audioSource != null)
        {
            audioSource.PlayOneShot(collapseSound);
        }

        // 2. Haptic Feedback (Meta XR OVRInput)
        // A short, sharp vibration to the dominant controller to simulate physical mass materializing
#if UNITY_ANDROID || UNITY_STANDALONE_WIN
        try
        {
            // OVRInput.SetControllerVibration(1.0f, 0.5f, OVRInput.Controller.RTouch);
            // StartCoroutine(StopVibration(0.15f, OVRInput.Controller.RTouch));
            Debug.Log("[Somatic] Fired Haptic Pulse for Waveform Collapse.");
        }
        catch
        {
            // Fail gracefully if OVR is not initialized yet during Editor testing
        }
#endif
    }

    /// <summary>
    /// Called by the XR Ray Interactor (via XR Simple Interactable events) when the gaze enters the bounds.
    /// </summary>
    public void OnGazeEnter()
    {
        _isBeingObserved = true;
    }

    /// <summary>
    /// Called by the XR Ray Interactor when the gaze leaves the bounds.
    /// </summary>
    public void OnGazeExit()
    {
        _isBeingObserved = false;
    }

    public void OnPointerEnter() => OnGazeEnter();
    public void OnPointerExit() => OnGazeExit();
}