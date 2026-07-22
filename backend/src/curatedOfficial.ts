import type { SourceArticle } from "./domain/article";
import { isTrustedChineseNewswireURL } from "./domain/credibility";
import { normalizeArticle } from "./pipeline/filter";

export const CURATED_OFFICIAL_KEY = "official:curated";
const MAX_CURATED_BYTES = 16_384;
const BUILT_IN_PUBLISHED_AT_MS = Date.parse("2026-06-24T12:00:00Z");
const OFFICIAL_PATH = /^\/(?:zh|zh-hans|zh-hant)\/newswire\/article\/[^/]+\/[^/]+\/?$/iu;

const BUILT_IN_OFFICIAL: SourceArticle = Object.freeze<SourceArticle>({
  id: "5171972o3ak5oa",
  title: "6月25日Grand Theft Auto VI开启预购",
  summary: "Rockstar Games 宣布《Grand Theft Auto VI》现已开启全球预购，并介绍版本、预载与奖励安排。",
  sourceName: "Rockstar Games",
  sourceURL: "https://www.rockstargames.com/zh/newswire/article/5171972o3ak5oa/pre-order-grand-theft-auto-vi-on-june-25",
  publishedAt: "2026-06-24T12:00:00Z",
  imageURL: "https://media-rockstargames-com.akamaized.net/tina-uploads/posts/5171972o3ak5oa/b256fa44c02682ba4bf925c4d0935d05d957130d.jpg",
  adapter: { id: "rockstar-newswire", kind: "officialCandidate" },
  upstreamTopicKey: "official-preorder-2026-06-25",
  isPinned: true
});

function candidateFromKV(serialized: string | null, now: Date): SourceArticle | null {
  if (serialized === null || serialized.length > MAX_CURATED_BYTES
    || new TextEncoder().encode(serialized).byteLength > MAX_CURATED_BYTES) return null;
  let value: unknown;
  try { value = JSON.parse(serialized); } catch { return null; }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const allowed = ["title", "summary", "sourceURL", "publishedAt", "imageURL"].sort();
  const keys = Object.keys(record).sort();
  if (keys.length !== allowed.length || !keys.every((key, index) => key === allowed[index])
    || typeof record.title !== "string" || typeof record.summary !== "string"
    || typeof record.sourceURL !== "string" || typeof record.publishedAt !== "string"
    || (record.imageURL !== null && typeof record.imageURL !== "string")) return null;
  let url: URL;
  try { url = new URL(record.sourceURL); } catch { return null; }
  if (!isTrustedChineseNewswireURL(url.href) || !OFFICIAL_PATH.test(url.pathname)) return null;
  const pathID = url.pathname.split("/").filter(Boolean).at(-2);
  if (!pathID) return null;
  const candidate: SourceArticle = {
    id: pathID,
    title: record.title,
    summary: record.summary,
    sourceName: "Rockstar Games",
    sourceURL: url.href,
    publishedAt: record.publishedAt,
    imageURL: record.imageURL,
    adapter: { id: "rockstar-newswire", kind: "officialCandidate" },
    upstreamTopicKey: `official-${pathID}`,
    isPinned: true
  };
  const normalized = normalizeArticle(candidate);
  const publishedAt = normalized ? Date.parse(normalized.publishedAt) : Number.NaN;
  return normalized?.isOfficial === true && publishedAt >= BUILT_IN_PUBLISHED_AT_MS
    && publishedAt <= now.getTime() + 5 * 60 * 1_000 ? candidate : null;
}

/** Returns the audited built-in record unless a private KV override passes every trust boundary. */
export function resolveCuratedOfficial(serialized: string | null, now: Date): SourceArticle {
  return candidateFromKV(serialized, now) ?? BUILT_IN_OFFICIAL;
}
