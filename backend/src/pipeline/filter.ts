import type { PipelineArticle, SourceArticle } from "../domain/article";
import { classifyCredibility } from "../domain/credibility";
import { convertArticleTextToSimplified } from "./traditionalToSimplified";

const GTA_VI_PATTERNS = [
  /\bgta\s*(?:vi|6)\b/i,
  /\bgrand\s+theft\s+auto\s*(?:vi|6)(?:\b|(?=[\u3400-\u9fff]))/i,
  /侠盗猎车手\s*(?:vi|6|六)/i,
  /俠盜獵車手\s*(?:vi|6|六)/i
];

function withoutAllowedProperNames(value: string): string {
  return value
    .replace(/\b(?:gta\s*(?:vi|6)|grand\s+theft\s+auto\s*(?:vi|6))\b/gi, "")
    .replace(/\brockstar(?:\s+games)?\b/gi, "");
}

function hasSubstantiveChinese(value: string, minimumCharacters: number, minimumRatio = 0.5): boolean {
  const editorialText = withoutAllowedProperNames(value.normalize("NFKC"));
  const chineseCount = editorialText.match(/[\u3400-\u9fff]/gu)?.length ?? 0;
  const wordLikeCount = editorialText.match(/[\p{L}\p{N}]/gu)?.length ?? 0;
  return chineseCount >= minimumCharacters
    && wordLikeCount > 0
    && chineseCount / wordLikeCount >= minimumRatio;
}

export function isGTAVIRelevant(article: Pick<SourceArticle, "title" | "summary">): boolean {
  const text = `${article.title} ${article.summary}`.normalize("NFKC");
  return hasSubstantiveChinese(article.title, 3, 0.3)
    && hasSubstantiveChinese(article.summary, 4)
    && GTA_VI_PATTERNS.some((pattern) => pattern.test(text));
}

const MAX_URL_LENGTH = 2_048;
const MAX_RAW_ID_LENGTH = 256;
const MAX_STABLE_ID_LENGTH = 2_500;
const MAX_RELATED_SOURCE_COUNT = 99;
const ADAPTER_ID = /^[a-z0-9](?:[a-z0-9._-]{0,63})$/;

function parseWebURL(value: string, requireHTTPS = false): URL | null {
  if (value.length > MAX_URL_LENGTH) return null;
  try {
    const url = new URL(value);
    if (
      (url.protocol !== "http:" && url.protocol !== "https:")
      || (requireHTTPS && url.protocol !== "https:")
      || !url.hostname
      || url.username !== ""
      || url.password !== ""
      || url.href.length > MAX_URL_LENGTH
    ) {
      return null;
    }
    return url;
  } catch {
    return null;
  }
}

function canonicalAdapterID(value: string): string | null {
  const adapterID = value.trim().toLocaleLowerCase("en-US");
  return ADAPTER_ID.test(adapterID) ? adapterID : null;
}

function stableArticleID(adapterID: string, rawID: string, sourceURL: string): string | null {
  const upstreamID = rawID.trim();
  if (
    upstreamID.length === 0
    || upstreamID.length > MAX_RAW_ID_LENGTH
    || /[\u0000-\u001f\u007f]/u.test(upstreamID)
  ) {
    return null;
  }
  const id = `v1|${adapterID.length}:${adapterID}|${upstreamID.length}:${upstreamID}|${sourceURL}`;
  return id.length <= MAX_STABLE_ID_LENGTH ? id : null;
}

function sanitizeRelatedSourceCount(value: number | undefined): number {
  if (value === undefined || !Number.isFinite(value)) return 0;
  return Math.min(MAX_RELATED_SOURCE_COUNT, Math.max(0, Math.trunc(value)));
}

function isPrivateIPv4(hostname: string): boolean {
  const parts = hostname.split(".");
  if (parts.length !== 4 || parts.some((part) => !/^\d{1,3}$/.test(part))) return false;
  const numbers = parts.map(Number);
  if (numbers.some((part) => part > 255)) return true;
  const [first, second] = numbers;
  return first === 0
    || first === 10
    || first === 127
    || (first === 100 && second >= 64 && second <= 127)
    || (first === 169 && second === 254)
    || (first === 172 && second >= 16 && second <= 31)
    || (first === 192 && second === 168)
    || (first === 198 && (second === 18 || second === 19))
    || first >= 224;
}

function isPrivateIPv6(hostname: string): boolean {
  const host = hostname.replace(/^\[|\]$/g, "").toLocaleLowerCase("en-US");
  if (!host.includes(":")) return false;
  if (host === "::" || host === "::1") return true;
  if (host.startsWith("::ffff:") || host.startsWith("0:0:0:0:0:ffff:")) return true;
  const first = Number.parseInt(host.split(":")[0] || "0", 16);
  return (first & 0xfe00) === 0xfc00
    || (first & 0xffc0) === 0xfe80
    || (first & 0xff00) === 0xff00;
}

function isPublicImageHost(hostname: string): boolean {
  const host = hostname
    .replace(/^\[|\]$/g, "")
    .replace(/\.+$/u, "")
    .toLocaleLowerCase("en-US");
  return host !== "localhost"
    && !host.endsWith(".localhost")
    && !host.endsWith(".local")
    && !isPrivateIPv4(host)
    && !isPrivateIPv6(host);
}

function parseImageURL(value: string): URL | null {
  const url = parseWebURL(value, true);
  return url && isPublicImageHost(url.hostname) ? url : null;
}

function parsePublishedAt(value: string): Date | null {
  const match = value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|([+-])(\d{2}):(\d{2}))$/
  );
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = Number(match[9] ?? 0);
  const offsetMinute = Number(match[10] ?? 0);
  const daysInMonth = month >= 1 && month <= 12
    ? new Date(Date.UTC(year, month, 0)).getUTCDate()
    : 0;
  if (
    year < 2020 || year > 2100
    || day < 1 || day > daysInMonth
    || hour > 23 || minute > 59 || second > 59
    || offsetHour > 14 || offsetMinute > 59
    || (offsetHour === 14 && offsetMinute !== 0)
  ) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : null;
}

function normalizedKey(value: string): string {
  return value
    .normalize("NFKC")
    .trim()
    .toLocaleLowerCase("en-US")
    .replace(/\b(?:gta\s*(?:vi|6)|grand\s+theft\s+auto\s*(?:vi|6))\b/gi, "gtavi")
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "");
}

export function normalizeArticle(input: SourceArticle): PipelineArticle | null {
  const article = convertArticleTextToSimplified(input);
  const credibility = classifyCredibility(article);
  const adapterID = canonicalAdapterID(article.adapter.id);
  const ownSourceURL = parseWebURL(article.sourceURL);
  const id = adapterID && ownSourceURL
    ? stableArticleID(adapterID, article.id, ownSourceURL.href)
    : null;
  const title = article.title.trim();
  const summary = article.summary.trim();
  const original = credibility === "official" ? null : article.originalSource ?? null;
  const originalAdapterID = original ? canonicalAdapterID(original.adapter.id) : null;
  const sourceName = (original?.sourceName ?? article.sourceName).trim();
  const sourceURLValue = original?.sourceURL ?? article.sourceURL;
  const sourceURL = parseWebURL(sourceURLValue);
  const publishedDate = parsePublishedAt(article.publishedAt);

  if (
    (article.isLeak === true && !article.originalSource)
    ||
    !id || !adapterID || !ownSourceURL || !title || !summary || !sourceName || !sourceURL || !publishedDate
    || (original !== null && originalAdapterID === null)
    || !isGTAVIRelevant(article)
  ) {
    return null;
  }

  const upstreamKey = normalizedKey(article.upstreamTopicKey ?? "");
  const titleKey = normalizedKey(title);
  const canonicalTopicKey = upstreamKey || titleKey || id;
  const imageURL = article.imageURL ? parseImageURL(article.imageURL) : null;

  return {
    id,
    title,
    summary,
    sourceName,
    sourceURL: sourceURL.href,
    publishedAt: publishedDate.toISOString(),
    imageURL: imageURL?.href ?? null,
    credibility,
    isOfficial: credibility === "official",
    isPinned: credibility === "official" && article.isPinned === true,
    relatedSourceCount: sanitizeRelatedSourceCount(article.relatedSourceCount),
    canonicalTopicKey,
    attributedAdapterID: originalAdapterID ?? adapterID,
    explicitTopicKey: upstreamKey || null
  };
}
