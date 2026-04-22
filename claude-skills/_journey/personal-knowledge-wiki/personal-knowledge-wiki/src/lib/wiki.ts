import fs from "fs";
import path from "path";
import matter from "gray-matter";

// UPDATE THIS PATH to point to your vault's wiki/ directory
const WIKI_DIR = path.join(
  process.env.WIKI_PATH || process.env.HOME || "",
  "wiki"
);

export interface WikiPage {
  slug: string;
  filename: string;
  folder: string;
  title: string;
  type: string;
  created: string;
  updated: string;
  tags: string[];
  sources: string[];
  content: string;
  backlinks: string[];
  outlinks: string[];
}

export interface WikiStats {
  totalPages: number;
  entities: number;
  concepts: number;
  sources: number;
  comparisons: number;
  syntheses: number;
  totalLinks: number;
}

const FOLDERS = ["entities", "concepts", "sources", "comparisons", "syntheses"];

function extractWikilinks(content: string): string[] {
  const matches = content.match(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g) || [];
  return matches.map((m) => {
    const inner = m.match(/\[\[([^\]|]+)/);
    return inner ? inner[1].toLowerCase().trim() : "";
  }).filter(Boolean);
}

function slugify(filename: string): string {
  return filename.replace(/\.md$/, "").toLowerCase();
}

export function getAllPages(): WikiPage[] {
  const pages: WikiPage[] = [];
  for (const folder of FOLDERS) {
    const folderPath = path.join(WIKI_DIR, folder);
    if (!fs.existsSync(folderPath)) continue;
    const files = fs.readdirSync(folderPath).filter((f) => f.endsWith(".md"));
    for (const file of files) {
      const filePath = path.join(folderPath, file);
      const raw = fs.readFileSync(filePath, "utf-8");
      const { data, content } = matter(raw);
      pages.push({
        slug: slugify(file),
        filename: file,
        folder,
        title: data.title || file.replace(/\.md$/, "").replace(/-/g, " "),
        type: data.type || folder.replace(/s$/, ""),
        created: data.created || "",
        updated: data.updated || "",
        tags: data.tags || [],
        sources: data.sources || [],
        content,
        backlinks: [],
        outlinks: extractWikilinks(content),
      });
    }
  }
  for (const page of pages) {
    for (const link of page.outlinks) {
      const target = pages.find((p) => p.slug === link);
      if (target && !target.backlinks.includes(page.slug)) {
        target.backlinks.push(page.slug);
      }
    }
  }
  return pages;
}

export function getPage(folder: string, slug: string): WikiPage | null {
  const pages = getAllPages();
  return pages.find((p) => p.folder === folder && p.slug === slug) || null;
}

export function getStats(): WikiStats {
  const pages = getAllPages();
  return {
    totalPages: pages.length,
    entities: pages.filter((p) => p.folder === "entities").length,
    concepts: pages.filter((p) => p.folder === "concepts").length,
    sources: pages.filter((p) => p.folder === "sources").length,
    comparisons: pages.filter((p) => p.folder === "comparisons").length,
    syntheses: pages.filter((p) => p.folder === "syntheses").length,
    totalLinks: pages.reduce((acc, p) => acc + p.outlinks.length, 0),
  };
}

export function searchPages(query: string): WikiPage[] {
  const pages = getAllPages();
  const q = query.toLowerCase();
  return pages.filter(
    (p) =>
      p.title.toLowerCase().includes(q) ||
      p.content.toLowerCase().includes(q) ||
      p.tags.some((t) => t.toLowerCase().includes(q))
  );
}
