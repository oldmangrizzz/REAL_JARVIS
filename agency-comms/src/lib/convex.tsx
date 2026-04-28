"use client";

import { ConvexProvider, ConvexReactClient } from "convex/react";
import { ReactNode, useMemo } from "react";
import { CONVEX_URL } from "./config";

export function ConvexClientProvider({ children }: { children: ReactNode }) {
  const client = useMemo(() => new ConvexReactClient(CONVEX_URL), []);
  return <ConvexProvider client={client}>{children}</ConvexProvider>;
}
