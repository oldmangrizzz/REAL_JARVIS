"use client";

import { useQuery } from "convex/react";
import { api } from "../../convex/_generated/api";
import { MAPBOX_TOKEN, HOME_COORDS, MARKER_COLORS } from "../lib/config";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Id } from "../../convex/_generated/dataModel";

type Marker = {
  _id: Id<"markers">;
  type: string;
  label: string;
  description?: string;
  latitude: number;
  longitude: number;
  color?: string;
  icon?: string;
  cardId?: Id<"cards">;
  agentId?: Id<"agents">;
  expiresAt?: number;
  createdAt: number;
};

type Card = {
  _id: Id<"cards">;
  title: string;
  latitude?: number;
  longitude?: number;
  priority: string;
  status: string;
};

function makeMarkerSvg(color: string, label: string, size: number = 28): string {
  const text = label.substring(0, 3).toUpperCase();
  const svg = `<svg width="${size}" height="${size + 10}" viewBox="0 0 28 38" xmlns="http://www.w3.org/2000/svg">
    <path d="M14 0C6.268 0 0 6.268 0 14c0 10.5 14 24 14 24s14-13.5 14-24C28 6.268 21.732 0 14 0z" fill="${color}" stroke="#0a0a0f" stroke-width="1"/>
    <text x="14" y="16" text-anchor="middle" fill="#e8e8f0" font-size="8" font-weight="bold" font-family="monospace">${text}</text>
  </svg>`;
  return `data:image/svg+xml;base64,${btoa(svg)}`;
}

function sanitizeAttribute(str: string): string {
  return str.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export function SituationalMap({ onMarkerClick }: { onMarkerClick?: (markerId: Id<"markers">) => void }) {
  const markers = useQuery(api.markers.list);
  const cards = useQuery(api.cards.list, {});
  const mapContainer = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<Map<string, any>>(new Map());
  const [mapLoaded, setMapLoaded] = useState(false);

  useEffect(() => {
    if (!mapContainer.current || mapRef.current || !MAPBOX_TOKEN) return;

    import("mapbox-gl").then((mapboxgl) => {
      import("mapbox-gl/dist/mapbox-gl.css");
      const map = new mapboxgl.Map({
        container: mapContainer.current!,
        style: "mapbox://styles/mapbox/dark-v11",
        center: [HOME_COORDS.longitude, HOME_COORDS.latitude],
        zoom: HOME_COORDS.zoom,
        accessToken: MAPBOX_TOKEN,
      });

      map.addControl(new mapboxgl.NavigationControl(), "bottom-right");
      map.addControl(new mapboxgl.ScaleControl(), "bottom-left");

      map.on("load", () => setMapLoaded(true));
      mapRef.current = map;
    });

    return () => {
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  const syncMarkers = useCallback(() => {
    const map = mapRef.current;
    if (!map || !markers || !cards) return;

    const mapboxgl = require("mapbox-gl");
    const existingIds = new Set(markersRef.current.keys());
    const currentIds = new Set<string>();

    for (const m of markers) {
      const id = m._id;
      currentIds.add(id);
      if (markersRef.current.has(id)) continue;

      const el = document.createElement("div");
      el.className = "marker-popup";
      el.style.cursor = "pointer";

      const safeLabel = sanitizeAttribute(m.label);
      const safeDesc = m.description ? sanitizeAttribute(m.description) : "";
      const safeType = sanitizeAttribute(m.type.toUpperCase());
      const mColor = m.color || MARKER_COLORS[m.type] || "#888";

      const popup = new mapboxgl.Popup({ offset: 12, closeButton: false });
      popup.setDOMContent(() => {
        const container = document.createElement("div");
        container.style.fontFamily = "monospace";
        container.style.fontSize = "12px";
        const title = document.createElement("div");
        title.style.fontWeight = "bold";
        title.style.color = mColor;
        title.textContent = m.label;
        container.appendChild(title);
        if (m.description) {
          const desc = document.createElement("div");
          desc.style.color = "#8888a0";
          desc.style.marginTop = "4px";
          desc.textContent = m.description;
          container.appendChild(desc);
        }
        const typeEl = document.createElement("div");
        typeEl.style.color = "#555570";
        typeEl.style.marginTop = "2px";
        typeEl.textContent = m.type.toUpperCase();
        container.appendChild(typeEl);
        return container;
      });

      const marker = new mapboxgl.Marker({ element: el })
        .setLngLat([m.longitude, m.latitude])
        .setPopup(popup)
        .addTo(map);

      const img = document.createElement("img");
      img.src = makeMarkerSvg(mColor, m.label);
      img.style.width = "28px";
      img.style.height = "38px";
      el.appendChild(img);

      if (onMarkerClick) {
        el.addEventListener("click", () => onMarkerClick(m._id));
      }

      markersRef.current.set(id, marker);
    }

    const cardsWithLocation = cards.filter((c: Card) => c.latitude && c.longitude);
    for (const c of cardsWithLocation) {
      const id = `card-${c._id}`;
      currentIds.add(id);
      if (markersRef.current.has(id)) continue;

      const el = document.createElement("div");
      el.style.cursor = "pointer";
      const color = c.priority === "immediate" ? "#ef4444" : c.priority === "priority" ? "#f59e0b" : "#3b82f6";

      const img = document.createElement("img");
      img.src = makeMarkerSvg(color, c.title);
      img.style.width = "28px";
      img.style.height = "38px";
      el.appendChild(img);

      const popup = new mapboxgl.Popup({ offset: 12, closeButton: false });
      popup.setDOMContent(() => {
        const container = document.createElement("div");
        container.style.fontFamily = "monospace";
        container.style.fontSize = "12px";
        const title = document.createElement("div");
        title.style.fontWeight = "bold";
        title.style.color = color;
        title.textContent = c.title;
        container.appendChild(title);
        const status = document.createElement("div");
        status.style.color = "#8888a0";
        status.style.marginTop = "2px";
        status.textContent = `${c.status.toUpperCase()} — ${c.priority.toUpperCase()}`;
        container.appendChild(status);
        return container;
      });

      const marker = new mapboxgl.Marker({ element: el })
        .setLngLat([c.longitude!, c.latitude!])
        .setPopup(popup)
        .addTo(map);

      markersRef.current.set(id, marker);
    }

    for (const id of existingIds) {
      if (!currentIds.has(id)) {
        markersRef.current.get(id)?.remove();
        markersRef.current.delete(id);
      }
    }
  }, [markers, cards, onMarkerClick]);

  useEffect(() => {
    if (mapLoaded) syncMarkers();
  }, [mapLoaded, syncMarkers]);

  return (
    <div className="relative w-full h-full">
      <div ref={mapContainer} className="w-full h-full" />
      {!mapLoaded && (
        <div className="absolute inset-0 flex items-center justify-center bg-[#0a0a0f]/80">
          <div className="text-[#555570] text-xs font-mono">Initializing tactical overlay...</div>
        </div>
      )}
    </div>
  );
}