export const LIVEKIT_URL = process.env.NEXT_PUBLIC_LIVEKIT_URL ?? "";
export const MAPBOX_TOKEN = process.env.NEXT_PUBLIC_MAPBOX_TOKEN ?? "";
export const CONVEX_URL = process.env.NEXT_PUBLIC_CONVEX_URL ?? "";

export const HOME_COORDS = { latitude: 32.7254, longitude: -97.3452, zoom: 12 };

export const PRIORITY_COLORS: Record<string, string> = {
  routine: "#3b82f6",
  priority: "#f59e0b",
  immediate: "#ef4444",
};

export const STATUS_COLORS: Record<string, string> = {
  online: "#10b981",
  idle: "#555570",
  working: "#f59e0b",
  blocked: "#ef4444",
  offline: "#555570",
};

export const MARKER_COLORS: Record<string, string> = {
  poi: "#3b82f6",
  hazard: "#ef4444",
  asset: "#10b981",
  agent: "#8b5cf6",
  event: "#f59e0b",
};

export const HARNESS_COLORS: Record<string, string> = {
  "claude-code": "#ef4444",
  "gemini-cli": "#3b82f6",
  "qwen-cli": "#f59e0b",
  "copilot-cli": "#10b981",
  hermes: "#8b5cf6",
};
