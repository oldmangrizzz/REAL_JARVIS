import Link from "next/link";
import { getAllPages, getStats } from "@/lib/wiki";

const TYPE_COLORS: Record<string, string> = {
  entity: "bg-blue-500/20 text-blue-300 border-blue-500/30",
  concept: "bg-purple-500/20 text-purple-300 border-purple-500/30",
  source: "bg-green-500/20 text-green-300 border-green-500/30",
  comparison: "bg-orange-500/20 text-orange-300 border-orange-500/30",
  synthesis: "bg-pink-500/20 text-pink-300 border-pink-500/30",
};

const TYPE_ICONS: Record<string, string> = {
  entity: "👤",
  concept: "💡",
  source: "📄",
  comparison: "⚖️",
  synthesis: "🧬",
};

export default function Home() {
  const pages = getAllPages();
  const stats = getStats();
  const folders = ["entities", "concepts", "sources", "comparisons", "syntheses"];

  return (
    <main className="min-h-screen bg-black text-white">
      <div className="border-b border-white/10 px-8 py-6">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold tracking-wider font-mono">PERSONAL WIKI</h1>
            <p className="text-white/40 text-sm mt-1 font-mono">Knowledge base — maintained by Librarian</p>
          </div>
          <div className="flex gap-6 text-sm font-mono text-white/50">
            <div><span className="text-white font-bold">{stats.totalPages}</span> pages</div>
            <div><span className="text-white font-bold">{stats.totalLinks}</span> links</div>
          </div>
        </div>
      </div>
      <div className="px-8 py-6 border-b border-white/5">
        <div className="max-w-6xl mx-auto">
          <Link href="/search" className="block w-full max-w-md bg-white/5 border border-white/10 rounded px-4 py-3 text-white/30 font-mono text-sm hover:border-white/20 transition-colors">
            Search the wiki...
          </Link>
        </div>
      </div>
      <div className="px-8 py-8">
        <div className="max-w-6xl mx-auto grid grid-cols-5 gap-4">
          {folders.map((folder) => {
            const type = folder.replace(/s$/, "");
            const count = pages.filter((p) => p.folder === folder).length;
            return (
              <Link key={folder} href={"/" + folder} className={"border rounded-lg p-4 hover:bg-white/5 transition-colors " + (TYPE_COLORS[type] || "border-white/10")}>
                <div className="text-2xl mb-2">{TYPE_ICONS[type]}</div>
                <div className="text-2xl font-bold font-mono">{count}</div>
                <div className="text-xs uppercase tracking-wider mt-1 opacity-70">{folder}</div>
              </Link>
            );
          })}
        </div>
      </div>
      <div className="px-8 py-4">
        <div className="max-w-6xl mx-auto">
          <h2 className="text-lg font-bold font-mono mb-4 text-white/70">All Pages</h2>
          {pages.length === 0 ? (
            <div className="text-center py-20 text-white/30 font-mono">
              <p className="text-4xl mb-4">📚</p>
              <p className="text-lg">Wiki is empty</p>
              <p className="text-sm mt-2">Drop sources into <code className="bg-white/10 px-2 py-0.5 rounded">raw/</code> and ask the Librarian to ingest them.</p>
            </div>
          ) : (
            <div className="space-y-2">
              {pages.sort((a, b) => String(b.updated || b.created).localeCompare(String(a.updated || a.created))).map((page) => (
                <Link key={page.folder + "/" + page.slug} href={"/" + page.folder + "/" + page.slug} className="block border border-white/5 rounded-lg px-5 py-3 hover:bg-white/5 hover:border-white/10 transition-colors group">
                  <div className="flex items-center gap-3">
                    <span className="text-lg">{TYPE_ICONS[page.type] || "📝"}</span>
                    <div className="flex-1">
                      <span className="font-mono text-sm group-hover:text-white transition-colors">{page.title}</span>
                    </div>
                    <span className={"text-[10px] uppercase tracking-wider px-2 py-0.5 rounded border " + (TYPE_COLORS[page.type] || "")}>{page.type}</span>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </div>
      </div>
      <div className="px-8 py-8 mt-8 border-t border-white/5">
        <div className="max-w-6xl mx-auto text-center text-xs text-white/20 font-mono">
          Maintained by Librarian · Powered by Obsidian + Next.js
        </div>
      </div>
    </main>
  );
}
