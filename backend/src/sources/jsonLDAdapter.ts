import type { SourceArticle } from "../domain/article";
import type { AdapterParseResult, SourceAdapter } from "./sourceAdapter";
import { findOriginalSource } from "./provenanceRegistry";

export interface JSONLDAdapterConfig {
  readonly id: string;
  readonly kind: "officialCandidate" | "media";
  readonly sourceName: string;
  readonly url: string;
  readonly baseURL: string;
  readonly trustedHosts: readonly string[];
  readonly imageHosts: readonly string[];
  readonly articlePathPattern: RegExp;
}

type JSONObject = Record<string, unknown>;

function hostAllowed(hostname: string, hosts: readonly string[]): boolean {
  const canonical = hostname.replace(/\.+$/u, "").toLocaleLowerCase("en-US");
  return hosts.some((host) => canonical === host || canonical.endsWith(`.${host}`));
}

function safeURL(value: unknown, baseURL: string, hosts: readonly string[], httpsOnly: boolean): string | null {
  if (typeof value !== "string" || value.length > 2_048) return null;
  try {
    const url = new URL(value, baseURL);
    if ((httpsOnly ? url.protocol !== "https:" : !["http:", "https:"].includes(url.protocol))
      || (url.port !== "" && url.port !== "443")
      || url.username || url.password || !hostAllowed(url.hostname, hosts) || url.href.length > 2_048) return null;
    if (url.protocol === "http:") url.protocol = "https:";
    return url.href;
  } catch {
    return null;
  }
}

function scalar(value: unknown): string {
  let current = value;
  const visited = new WeakSet<object>();
  for (let depth = 0; depth <= 16; depth += 1) {
    if (typeof current === "string") return current.trim();
    if (!current || typeof current !== "object" || visited.has(current) || !("@value" in current)) return "";
    visited.add(current);
    current = (current as JSONObject)["@value"];
  }
  return "";
}

function normalizedText(value: unknown): string {
  return scalar(value).replace(/\s+/gu, " ").trim();
}

function boundedText(value: unknown, maximumCodePoints: number, truncate: boolean): string {
  const text = normalizedText(value);
  const codePoints = Array.from(text);
  if (codePoints.length <= maximumCodePoints) return text;
  return truncate ? codePoints.slice(0, maximumCodePoints).join("").trimEnd() : "";
}

function boundedTopicKey(value: unknown): string | null {
  const key = normalizedText(value);
  return key && Array.from(key).length <= 120 && !/[\u0000-\u001f\u007f]/u.test(key) ? key : null;
}

function imageValue(value: unknown): unknown {
  let current = value;
  const visited = new WeakSet<object>();
  for (let depth = 0; depth <= 16; depth += 1) {
    if (!current || typeof current !== "object" || visited.has(current)) return current;
    visited.add(current);
    if (Array.isArray(current)) {
      current = current[0];
      continue;
    }
    current = (current as JSONObject).url ?? (current as JSONObject).contentUrl;
  }
  return null;
}

function validLocalDate(year: number, month: number, day: number, hour: number, minute: number, second: number): boolean {
  if (year < 2020 || year > 2100 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) return false;
  return day >= 1 && day <= new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export function chinaTimeToISO(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = value.trim().match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[T\s](\d{1,2}):(\d{2})(?::(\d{2}))?)?(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})?$/u);
  if (!match) return null;
  const [, y, m, d, hh = "0", mm = "0", ss = "0", zone] = match;
  const parts = [y, m, d, hh, mm, ss].map(Number);
  if (!validLocalDate(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])) return null;
  const normalized = `${y.padStart(4, "0")}-${m.padStart(2, "0")}-${d.padStart(2, "0")}T${hh.padStart(2, "0")}:${mm.padStart(2, "0")}:${ss.padStart(2, "0")}${zone ?? "+08:00"}`;
  const date = new Date(normalized);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function objectsIn(value: unknown): JSONObject[] {
  const objects: JSONObject[] = [];
  const stack: Array<{ value: unknown; depth: number }> = [{ value, depth: 0 }];
  const visited = new WeakSet<object>();
  let nodes = 0;
  while (stack.length > 0 && nodes < 256) {
    const next = stack.pop()!;
    nodes += 1;
    if (next.depth > 16 || !next.value || typeof next.value !== "object" || visited.has(next.value)) continue;
    visited.add(next.value);
    if (Array.isArray(next.value)) {
      for (let index = Math.min(next.value.length, 256) - 1; index >= 0; index -= 1) {
        stack.push({ value: next.value[index], depth: next.depth + 1 });
      }
      continue;
    }
    const object = next.value as JSONObject;
    objects.push(object);
    if (object["@graph"] !== undefined) stack.push({ value: object["@graph"], depth: next.depth + 1 });
  }
  return objects;
}

function jsonLDObjects(html: string): JSONObject[] {
  const objects: JSONObject[] = [];
  const scripts = html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script\s*>/giu);
  for (const script of scripts) {
    try { objects.push(...objectsIn(JSON.parse(script[1]))); } catch { /* one bad block must not poison the source */ }
  }
  return objects;
}

function decodeHTMLEntities(value: string): string {
  const codePoint = (raw: string, radix: number, original: string): string => {
    const number = Number.parseInt(raw, radix);
    return Number.isInteger(number) && number >= 0 && number <= 0x10ffff && !(number >= 0xd800 && number <= 0xdfff)
      ? String.fromCodePoint(number)
      : original;
  };
  return value
    .replace(/&#(\d+);?/gu, (original: string, decimal: string) => codePoint(decimal, 10, original))
    .replace(/&#x([0-9a-f]+);?/giu, (original: string, hexadecimal: string) => codePoint(hexadecimal, 16, original))
    .replace(/&quot;/giu, '"').replace(/&apos;|&#39;/giu, "'")
    .replace(/&lt;/giu, "<").replace(/&gt;/giu, ">").replace(/&amp;/giu, "&");
}

function attributes(tag: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const match of tag.matchAll(/([:\w-]+)\s*=\s*(["'])([\s\S]*?)\2/gu)) {
    result[match[1].toLocaleLowerCase("en-US")] = decodeHTMLEntities(match[3]).trim();
  }
  return result;
}

function metadata(html: string, key: string): string {
  for (const match of html.matchAll(/<meta\b[^>]*>/giu)) {
    const values = attributes(match[0]);
    if ([values.property, values.name, values.itemprop].some((value) => value?.toLocaleLowerCase("en-US") === key)) {
      return values.content ?? "";
    }
  }
  return "";
}

function firstMatch(html: string, patterns: readonly RegExp[]): string {
  for (const pattern of patterns) {
    const value = html.match(pattern)?.[1];
    if (value) return decodeHTMLEntities(value.replace(/<[^>]*>/gu, " ").replace(/\s+/gu, " ")).trim();
  }
  return "";
}

function metadataArticle(html: string, pageURL?: string): JSONObject | null {
  const title = metadata(html, "og:title") || metadata(html, "twitter:title")
    || firstMatch(html, [/<h1\b[^>]*>([\s\S]*?)<\/h1>/iu, /<title\b[^>]*>([\s\S]*?)<\/title>/iu]);
  const description = metadata(html, "og:description") || metadata(html, "description") || metadata(html, "twitter:description");
  const image = metadata(html, "og:image") || metadata(html, "image") || metadata(html, "twitter:image");
  const canonicalTag = html.match(/<link\b[^>]*\brel\s*=\s*["']canonical["'][^>]*>/iu)?.[0] ?? "";
  const canonical = attributes(canonicalTag).href;
  const published = metadata(html, "article:published_time") || metadata(html, "datepublished")
    || firstMatch(html, [
      /<time\b[^>]*\bdatetime\s*=\s*["']([^"']+)["']/iu,
      /\btitle\s*=\s*["']((?:20\d{2})[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(?::\d{2})?)["']/iu,
      /时间：\s*(?:<[^>]+>\s*)*((?:20\d{2})[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(?::\d{2})?)/iu,
      /((?:20\d{2})[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(?::\d{2})?)\s*(?:来源|出处)/iu,
      /class\s*=\s*["'][^"']*(?:time|date)[^"']*["'][^>]*>\s*((?:20\d{2})[-/]\d{1,2}[-/]\d{1,2}[ T]\d{1,2}:\d{2}(?::\d{2})?)/iu
    ]);
  if (!title || !description || !published || !(canonical || pageURL)) return null;
  return { "@type": "NewsArticle", headline: title, description, image, url: canonical || pageURL, datePublished: published };
}

function linkedProvenance(html: string): string[] {
  const links: string[] = [];
  for (const match of html.matchAll(/(?:转载自|出处|来源|原文)\s*[:：]?\s*(?:<\/?(?:span|strong|em|b|i)\b[^>]*>\s*){0,4}<a\b([^>]*)>/giu)) {
    const href = attributes(`<a ${match[1]}>`).href;
    if (href) links.push(href);
  }
  return links;
}

function isArticle(object: JSONObject): boolean {
  const types = Array.isArray(object["@type"]) ? object["@type"] : [object["@type"]];
  return types.some((type) => typeof type === "string" && /^(?:NewsArticle|Article)$/iu.test(type));
}

function stableRawID(sourceURL: string, identifier: unknown): string | null {
  const upstream = scalar(identifier);
  if (upstream.length > 0 && upstream.length <= 256 && !/[\u0000-\u001f\u007f]/u.test(upstream)) return upstream;
  const url = new URL(sourceURL);
  const candidate = `${url.pathname}${url.search}`.replace(/^\/+|\/+$/gu, "");
  if (candidate.length > 0 && candidate.length <= 256) return candidate;
  return null;
}

export function createJSONLDAdapter(config: JSONLDAdapterConfig): SourceAdapter {
  const adapter: SourceAdapter = {
    ...config,
    discover(html: string): readonly string[] {
      const discovered = new Set<string>();
      for (const match of html.matchAll(/\bhref\s*=\s*["']([^"']+)["']/giu)) {
        const url = safeURL(match[1], config.baseURL, config.trustedHosts, false);
        if (url && config.articlePathPattern.test(new URL(url).pathname + new URL(url).search)) discovered.add(url);
        config.articlePathPattern.lastIndex = 0;
      }
      return [...discovered];
    },
    parse(html: string, pageURL?: string): AdapterParseResult {
      try {
        if (typeof html !== "string" || html.length === 0) {
          return { ok: false, failure: { sourceID: config.id, stage: "parse", reason: "empty document" } };
        }
        const articles: SourceArticle[] = [];
        const metadataFallback = metadataArticle(html, pageURL);
        const candidates = [...jsonLDObjects(html), ...(metadataFallback ? [metadataFallback] : [])];
        const htmlProvenance = linkedProvenance(html);
        const seenURLs = new Set<string>();
        for (const object of candidates) {
          if (!isArticle(object)) continue;
          const title = boundedText(object.headline ?? object.name, 180, false);
          const summary = boundedText(object.description ?? object.abstract, 360, true);
          const sourceURL = safeURL(object.url ?? object.mainEntityOfPage ?? pageURL, config.baseURL, config.trustedHosts, false);
          const publishedAt = chinaTimeToISO(object.datePublished);
          if (!title || !summary || !sourceURL || !publishedAt) continue;
          const sourceLocation = new URL(sourceURL);
          config.articlePathPattern.lastIndex = 0;
          if (!config.articlePathPattern.test(sourceLocation.pathname + sourceLocation.search)) continue;
          config.articlePathPattern.lastIndex = 0;
          if (pageURL) {
            const requested = safeURL(pageURL, config.baseURL, config.trustedHosts, false);
            if (!requested) continue;
            const requestedLocation = new URL(requested);
            if (`${requestedLocation.pathname}${requestedLocation.search}` !== `${sourceLocation.pathname}${sourceLocation.search}`) continue;
          }
          const imageURL = safeURL(imageValue(object.image), config.baseURL, config.imageHosts, true);
          if (seenURLs.has(sourceURL)) continue;
          seenURLs.add(sourceURL);
          const id = stableRawID(sourceURL, object.identifier);
          if (!id) continue;
          const originalSource = findOriginalSource(htmlProvenance, config.id);
          articles.push({
            id, title, summary, sourceName: config.sourceName,
            sourceURL, publishedAt, imageURL, adapter: { id: config.id, kind: config.kind },
            upstreamTopicKey: boundedTopicKey(object.identifier),
            ...(originalSource ? { originalSource } : {})
          });
        }
        return articles.length > 0
          ? { ok: true, articles }
          : { ok: false, failure: { sourceID: config.id, stage: "parse", reason: "no valid NewsArticle metadata" } };
      } catch (error) {
        const reason = error instanceof Error ? error.message : "unexpected parser failure";
        return { ok: false, failure: { sourceID: config.id, stage: "parse", reason: reason.slice(0, 240) } };
      }
    }
  };
  return adapter;
}
