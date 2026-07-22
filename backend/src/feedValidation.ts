import type { FeedPayload } from "./aggregate";

export const MAX_STORED_FEED_BYTES = 1_000_000;
export const MAX_FEED_AGE_MS = 72 * 60 * 60 * 1_000;
const MAX_FUTURE_SKEW_MS = 5 * 60 * 1_000;
const CONTROL = /[\u0000-\u001f\u007f-\u009f]/u;

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function exactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const keys = Object.keys(value).sort();
  return keys.length === expected.length && keys.every((key, index) => key === [...expected].sort()[index]);
}

function cleanString(value: unknown, maximum: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maximum
    && value === value.trim() && !CONTROL.test(value);
}

function isoDate(value: unknown): Date | null {
  if (typeof value !== "string") return null;
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|([+-])(\d{2}):(\d{2}))$/u);
  if (!match) return null;
  const [, yearRaw, monthRaw, dayRaw, hourRaw, minuteRaw, secondRaw, , , offsetHourRaw = "0", offsetMinuteRaw = "0"] = match;
  const [year, month, day, hour, minute, second, offsetHour, offsetMinute] =
    [yearRaw, monthRaw, dayRaw, hourRaw, minuteRaw, secondRaw, offsetHourRaw, offsetMinuteRaw].map(Number);
  if (year < 2020 || year > 2100 || month < 1 || month > 12 || day < 1 || day > new Date(Date.UTC(year, month, 0)).getUTCDate()
    || hour > 23 || minute > 59 || second > 59 || offsetHour > 14 || offsetMinute > 59
    || (offsetHour === 14 && offsetMinute !== 0)) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

function webURL(value: unknown, nullable = false): boolean {
  if (nullable && value === null) return true;
  if (typeof value !== "string" || value.length > 2_048) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && Boolean(url.hostname)
      && url.username === "" && url.password === "";
  } catch { return false; }
}

function releaseDate(value: unknown): boolean {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (year < 2025 || year > 2035) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function validMilestones(value: unknown): boolean {
  const messages = record(value);
  if (!messages || Object.keys(messages).length > 32) return false;
  let bytes = 0;
  for (const [key, message] of Object.entries(messages)) {
    if (!/^\d{1,4}$/u.test(key) || Number(key) > 3650 || !cleanString(message, 120)) return false;
    bytes += new TextEncoder().encode(key).byteLength + new TextEncoder().encode(message).byteLength;
    if (bytes > 4_096) return false;
  }
  return true;
}

function validArticle(value: unknown): value is FeedPayload["articles"][number] {
  const article = record(value);
  if (!article || !exactKeys(article, [
    "id", "title", "summary", "sourceName", "sourceURL", "publishedAt", "imageURL",
    "credibility", "isOfficial", "isPinned", "relatedSourceCount", "canonicalTopicKey"
  ])) return false;
  const publishedAt = isoDate(article.publishedAt);
  const credibility = article.credibility;
  return cleanString(article.id, 2_500)
    && cleanString(article.title, 180)
    && cleanString(article.summary, 360)
    && cleanString(article.sourceName, 120)
    && webURL(article.sourceURL)
    && publishedAt !== null && publishedAt.getUTCFullYear() >= 2020 && publishedAt.getUTCFullYear() <= 2100
    && webURL(article.imageURL, true)
    && (credibility === "official" || credibility === "media" || credibility === "unverified")
    && typeof article.isOfficial === "boolean" && article.isOfficial === (credibility === "official")
    && typeof article.isPinned === "boolean" && (!article.isPinned || article.isOfficial)
    && Number.isInteger(article.relatedSourceCount) && Number(article.relatedSourceCount) >= 0 && Number(article.relatedSourceCount) <= 99
    && cleanString(article.canonicalTopicKey, 256);
}

function validRemoteConfig(value: unknown): value is FeedPayload["remoteConfig"] {
  const config = record(value);
  if (!config || !exactKeys(config, [
    "releaseDate", "releaseTimeMode", "milestoneMessages", "pinnedOfficialArticleID", "lastUpdatedAt", "schemaVersion"
  ])) return false;
  return releaseDate(config.releaseDate)
    && config.releaseTimeMode === "localMidnight"
    && validMilestones(config.milestoneMessages)
    && (config.pinnedOfficialArticleID === null || cleanString(config.pinnedOfficialArticleID, 2_500))
    && isoDate(config.lastUpdatedAt) !== null
    && config.schemaVersion === 1;
}

export function validateStoredFeed(serialized: string | null, now: Date): FeedPayload | null {
  if (serialized === null || serialized.length > MAX_STORED_FEED_BYTES || !Number.isFinite(now.getTime())
    || new TextEncoder().encode(serialized).byteLength > MAX_STORED_FEED_BYTES) return null;
  let parsed: unknown;
  try { parsed = JSON.parse(serialized); } catch { return null; }
  const payload = record(parsed);
  if (!payload || !exactKeys(payload, ["schemaVersion", "updatedAt", "remoteConfig", "articles"])
    || payload.schemaVersion !== 1 || !validRemoteConfig(payload.remoteConfig)
    || !Array.isArray(payload.articles) || payload.articles.length < 1 || payload.articles.length > 100
    || !payload.articles.every(validArticle)) return null;
  const updatedAt = isoDate(payload.updatedAt);
  if (!updatedAt || updatedAt.getTime() > now.getTime() + MAX_FUTURE_SKEW_MS
    || now.getTime() - updatedAt.getTime() > MAX_FEED_AGE_MS) return null;
  const articles = payload.articles as FeedPayload["articles"];
  const ids = new Set(articles.map((article) => article.id));
  if (ids.size !== articles.length) return null;
  if (articles.some((article) => isoDate(article.publishedAt)!.getTime() > now.getTime() + MAX_FUTURE_SKEW_MS)) return null;
  const configUpdatedAt = isoDate((payload.remoteConfig as FeedPayload["remoteConfig"]).lastUpdatedAt)!;
  if (configUpdatedAt.getTime() > now.getTime() + MAX_FUTURE_SKEW_MS) return null;
  const pinned = articles.filter((article) => article.isPinned);
  const pinnedID = (payload.remoteConfig as FeedPayload["remoteConfig"]).pinnedOfficialArticleID;
  if ((pinnedID === null && pinned.length !== 0)
    || (pinnedID !== null && (pinned.length !== 1 || pinned[0].id !== pinnedID))) return null;
  return payload as unknown as FeedPayload;
}
