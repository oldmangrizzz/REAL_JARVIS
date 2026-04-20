using UnityEngine;

// HoloPanel — a floating Iron-Man-style wireframe panel.
// Hover = emerald pulse. Focus = silver outline. Alert = crimson glitch.
public class HoloPanel : MonoBehaviour
{
    public enum State { Idle, Hover, Focus, Alert }

    [SerializeField] Material material;
    [SerializeField] Color emerald = new Color(0.314f, 0.784f, 0.471f);
    [SerializeField] Color silver  = new Color(0.753f, 0.753f, 0.753f);
    [SerializeField] Color crimson = new Color(0.863f, 0.078f, 0.235f);

    State state = State.Idle;
    float t;

    void Update()
    {
        t += Time.deltaTime;
        if (material == null) return;
        Color target = state switch {
            State.Hover => emerald,
            State.Focus => silver,
            State.Alert => crimson,
            _           => emerald * 0.35f
        };
        float pulse = 0.85f + 0.15f * Mathf.Sin(t * (state == State.Alert ? 12f : 2f));
        material.SetColor("_EmissionColor", target * pulse);
    }

    public void SetState(State s) { state = s; }
}
