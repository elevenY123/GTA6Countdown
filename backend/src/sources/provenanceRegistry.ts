import type { OriginalSource, SourceAdapterIdentity } from "../domain/article";

interface ProvenanceSource {
  readonly name: string;
  readonly adapter: SourceAdapterIdentity;
  readonly hosts: readonly string[];
  readonly articlePath: RegExp;
}

const SOURCES: readonly ProvenanceSource[] = [
  { name: "Rockstar Games", adapter: { id: "rockstar-newswire", kind: "officialCandidate" }, hosts: ["rockstargames.com"], articlePath: /^\/(?:zh|zh-hans|zh-hant)\/newswire\/article\/[a-z0-9]+\//iu },
  { name: "游民星空", adapter: { id: "gamersky", kind: "media" }, hosts: ["gamersky.com"], articlePath: /^\/news\/\d{6}\/\d+\.shtml$/u },
  { name: "3DM", adapter: { id: "3dm", kind: "media" }, hosts: ["3dmgame.com"], articlePath: /^\/news\/\d{6}\/\d+\.html$/u },
  { name: "机核", adapter: { id: "gcores", kind: "media" }, hosts: ["gcores.com"], articlePath: /^\/articles\/\d+$/u },
  { name: "巴哈姆特 GNN", adapter: { id: "bahamut-gnn", kind: "media" }, hosts: ["gamer.com.tw"], articlePath: /^\/detail\.php\?sn=\d+$/u },
  { name: "4Gamers", adapter: { id: "4gamers", kind: "media" }, hosts: ["4gamers.com.tw"], articlePath: /^\/news\/detail\/\d+\/[a-z0-9-]+$/u },
  { name: "联合新闻网游戏角落", adapter: { id: "udn-game", kind: "media" }, hosts: ["udn.com"], articlePath: /^\/game\/story\/\d+\/\d+$/u },
  { name: "IT之家", adapter: { id: "ithome", kind: "media" }, hosts: ["ithome.com"], articlePath: /^\/(?:0\/\d+\/\d+|html\/\d+)\.htm$/u },
  { name: "快科技", adapter: { id: "mydrivers", kind: "media" }, hosts: ["mydrivers.com"], articlePath: /^\/1\/\d+\/\d+\.htm$/u },
  { name: "游戏时光", adapter: { id: "vgtime", kind: "media" }, hosts: ["vgtime.com"], articlePath: /^\/news\/[A-Za-z0-9%+=_-]+$/u },
  { name: "Gamebase", adapter: { id: "gamebase", kind: "media" }, hosts: ["gamebase.com.tw"], articlePath: /^\/news\/detail\/\d+$/u }
];

// Task 12 should derive adapter construction from the same descriptors. Until
// then this exported projection keeps identity drift covered by a contract test.
export const PROVENANCE_SOURCE_IDENTITIES = SOURCES.map((source) => ({
  id: source.adapter.id,
  kind: source.adapter.kind,
  sourceName: source.name
}));

function candidateURLs(value: unknown): string[] {
  const urls: string[] = [];
  const stack: Array<{ value: unknown; depth: number }> = [{ value, depth: 0 }];
  const visited = new WeakSet<object>();
  let nodes = 0;
  while (stack.length > 0 && nodes < 256) {
    const next = stack.pop()!;
    nodes += 1;
    if (next.depth > 16) continue;
    if (typeof next.value === "string") {
      urls.push(next.value);
      continue;
    }
    if (!next.value || typeof next.value !== "object" || visited.has(next.value)) continue;
    visited.add(next.value);
    if (Array.isArray(next.value)) {
      for (let index = Math.min(next.value.length, 256) - 1; index >= 0; index -= 1) {
        stack.push({ value: next.value[index], depth: next.depth + 1 });
      }
      continue;
    }
    const object = next.value as Record<string, unknown>;
    stack.push(
      { value: object.sameAs, depth: next.depth + 1 },
      { value: object["@id"], depth: next.depth + 1 },
      { value: object.url, depth: next.depth + 1 }
    );
  }
  return urls;
}

function registeredSource(value: string, currentAdapterID: string): OriginalSource | null {
  if (value.length > 2_048) return null;
  try {
    const url = new URL(value);
    if (url.href.length > 2_048 || url.protocol !== "https:" || (url.port !== "" && url.port !== "443") || url.username || url.password) return null;
    url.hash = "";
    const host = url.hostname.replace(/\.+$/u, "").toLocaleLowerCase("en-US");
    const source = SOURCES.find((entry) => {
      const trustedHost = entry.hosts.some((candidate) => host === candidate || host.endsWith(`.${candidate}`));
      entry.articlePath.lastIndex = 0;
      const trustedPath = entry.articlePath.test(`${url.pathname}${url.search}`);
      entry.articlePath.lastIndex = 0;
      return trustedHost && trustedPath;
    });
    if (!source || source.adapter.id === currentAdapterID) return null;
    return { sourceName: source.name, sourceURL: url.href, adapter: source.adapter };
  } catch {
    return null;
  }
}

export function findOriginalSource(values: readonly unknown[], currentAdapterID: string): OriginalSource | null {
  for (const value of values) {
    for (const url of candidateURLs(value)) {
      const source = registeredSource(url, currentAdapterID);
      if (source) return source;
    }
  }
  return null;
}
