"use client";

import { ConvexClientProvider } from "../lib/convex";
import { AgentStatusBar } from "../components/AgentStatusBar";
import { CommandStream } from "../components/CommandStream";
import { SituationalMap } from "../components/SituationalMap";
import { useState } from "react";
import { useMutation } from "convex/react";
import { api } from "../../convex/_generated/api";

function SeedButton() {
  const seedAll = useMutation(api.seed.all);
  return (
    <button
      onClick={() => seedAll({})}
      className="bg-[#8b5cf6] hover:bg-[#7c3aed] text-white px-3 py-1 rounded text-[10px] font-bold tracking-wider"
    >
      SEED DATA
    </button>
  );
}

function Header() {
  const now = new Date();
  const timeStr = now.toLocaleTimeString("en-US", { hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const dateStr = now.toLocaleDateString("en-US", { weekday: "short", year: "numeric", month: "short", day: "numeric" });

  return (
    <div className="h-8 border-b border-[#2a2a40] bg-[#0a0a0f] flex items-center px-3 justify-between">
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-1.5">
          <span className="text-[#ef4444] font-black text-sm tracking-tighter">GMRI</span>
          <span className="text-[#555570] text-[10px]">AGENCY COMMS</span>
        </div>
        <div className="w-px h-3 bg-[#2a2a40]" />
        <span className="text-[10px] text-[#555570] font-mono">TACTICAL OPERATIONS CENTER</span>
      </div>
      <div className="flex items-center gap-3">
        <SeedButton />
        <div className="w-px h-3 bg-[#2a2a40]" />
        <span className="text-[10px] text-[#555570] font-mono">{dateStr}</span>
        <span className="text-[10px] text-[#e8e8f0] font-mono font-bold">{timeStr} LOCAL</span>
      </div>
    </div>
  );
}

function OpsCenter() {
  const [mapVisible, setMapVisible] = useState(false);

  return (
    <div className="h-full flex flex-col bg-[#0a0a0f]">
      <Header />
      <AgentStatusBar />
      <div className="flex-1 flex min-h-0">
        <div className="flex-1 flex flex-col min-w-0">
          <CommandStream />
        </div>
        {mapVisible && (
          <div className="w-96 border-l border-[#2a2a40] flex flex-col">
            <div className="flex items-center justify-between px-3 py-1.5 border-b border-[#2a2a40] bg-[#0a0a0f]">
              <span className="text-[10px] font-bold tracking-wider text-[#555570]">SITMAP</span>
              <button
                onClick={() => setMapVisible(false)}
                className="text-[10px] text-[#555570] hover:text-[#e8e8f0] transition-colors"
              >
                CLOSE
              </button>
            </div>
            <div className="flex-1 min-h-0">
              <SituationalMap />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <ConvexClientProvider>
      <OpsCenter />
    </ConvexClientProvider>
  );
}