import { toNewsArticle, type NormalizedArticle } from "./domain/article";
import { deduplicateArticles } from "./pipeline/dedupe";
import { normalizeArticle } from "./pipeline/filter";
import { defaultRemoteConfig, resolveRemoteConfig, SCHEMA_VERSION, type WorkerRemoteConfig } from "./config/defaultConfig";
import { gamerskyAdapter } from "./sources/gamersky";
import { mydriversAdapter } from "./sources/mydrivers";
import { runSourceAdapters, type AdapterBatchResult, type RunnerOptions } from "./sources/sourceAdapter";
import { validateStoredFeed } from "./feedValidation";
import { CURATED_OFFICIAL_KEY, resolveCuratedOfficial } from "./curatedOfficial";

export const FEED_KEY = "feed:latest";
export const STATUS_KEY = "fetch:status";
export const REMOTE_CONFIG_KEY = "config:remote";

export interface KVNamespaceLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

export interface WorkerEnv {
  readonly NEWS_KV: KVNamespaceLike;
}

export interface FeedPayload {
  readonly schemaVersion: number;
  readonly updatedAt: string;
  readonly remoteConfig: WorkerRemoteConfig;
  readonly articles: readonly NormalizedArticle[];
}

interface FetchStatus {
  readonly outcome: "success" | "fallback" | "unavailable";
  readonly checkedAt: string;
  readonly articleCount: number;
  readonly failureCount: number;
  readonly sourceFailures: readonly { sourceID: string; stage: string; reason: string }[];
}

type RunAdapters = (adapters: Parameters<typeof runSourceAdapters>[0], options?: RunnerOptions) => Promise<AdapterBatchResult>;

export interface AggregateDependencies {
  readonly now?: () => Date;
  readonly deadlineMs?: number;
  readonly runAdapters?: RunAdapters;
}

export type AggregateResult =
  | { readonly kind: "fresh"; readonly payload: FeedPayload }
  | { readonly kind: "cached"; readonly payload: string }
  | { readonly kind: "unavailable" };

// Only sources whose live paths were verified are enabled in production.
export const LIVE_SOURCE_ADAPTERS = Object.freeze([
  gamerskyAdapter,
  mydriversAdapter
]);

function safeJSON(value: string | null): unknown {
  if (value === null || value.length > 1_000_000) return null;
  try { return JSON.parse(value); } catch { return null; }
}

async function runWithDeadline(run: RunAdapters, deadlineMs: number): Promise<AdapterBatchResult> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<AdapterBatchResult>((resolve) => {
    timer = setTimeout(() => {
      controller.abort("batch deadline exceeded");
      resolve({
        articles: [],
        failures: LIVE_SOURCE_ADAPTERS.map((adapter) => ({
          sourceID: adapter.id,
          stage: "timeout" as const,
          reason: "batch deadline exceeded"
        }))
      });
    }, Math.max(1, Math.min(60_000, Math.trunc(deadlineMs))));
  });
  const batch = Promise.resolve().then(() => run(LIVE_SOURCE_ADAPTERS, { signal: controller.signal })).catch(() => ({
    articles: [],
    failures: LIVE_SOURCE_ADAPTERS.map((adapter) => ({
      sourceID: adapter.id,
      stage: "fetch" as const,
      reason: "adapter batch failed"
    }))
  }));
  try {
    return await Promise.race([batch, deadline]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

async function status(env: WorkerEnv, value: FetchStatus): Promise<void> {
  try { await env.NEWS_KV.put(STATUS_KEY, JSON.stringify(value)); } catch { /* status is best effort */ }
}

async function optionalGet(env: WorkerEnv, key: string): Promise<string | null> {
  try { return await env.NEWS_KV.get(key); } catch { return null; }
}

export async function aggregateAndStore(
  env: WorkerEnv,
  dependencies: AggregateDependencies = {}
): Promise<AggregateResult> {
  const now = dependencies.now?.() ?? new Date();
  const batch = await runWithDeadline(dependencies.runAdapters ?? runSourceAdapters, dependencies.deadlineMs ?? 20_000);
  const liveArticles = batch.articles.map(normalizeArticle).filter((article) => article !== null);
  const curated = liveArticles.length > 0
    ? normalizeArticle(resolveCuratedOfficial(await optionalGet(env, CURATED_OFFICIAL_KEY), now))
    : null;
  const normalized = curated === null ? liveArticles : [...liveArticles, curated];
  const deduplicated = deduplicateArticles(normalized);
  const pinnedOfficialArticleID = deduplicated.find((article) => article.isOfficial)?.id ?? null;
  const articles = deduplicated.map((article) => toNewsArticle({
    ...article,
    isPinned: article.id === pinnedOfficialArticleID
  }));
  const sourceFailures = batch.failures.map(({ sourceID, stage, reason }) => ({ sourceID, stage, reason }));

  if (articles.length > 0) {
    const storedConfig = safeJSON(await optionalGet(env, REMOTE_CONFIG_KEY));
    const remoteConfig = storedConfig === null
      ? defaultRemoteConfig(now, pinnedOfficialArticleID)
      : resolveRemoteConfig(storedConfig, now, pinnedOfficialArticleID);
    const payload: FeedPayload = {
      schemaVersion: SCHEMA_VERSION,
      updatedAt: now.toISOString(),
      remoteConfig,
      articles
    };
    const serialized = JSON.stringify(payload);
    if (validateStoredFeed(serialized, now) !== null) {
      await env.NEWS_KV.put(FEED_KEY, serialized);
      await status(env, {
        outcome: "success",
        checkedAt: now.toISOString(),
        articleCount: articles.length,
        failureCount: sourceFailures.length,
        sourceFailures
      });
      return { kind: "fresh", payload };
    }
  }

  const cachedText = await optionalGet(env, FEED_KEY);
  const cached = validateStoredFeed(cachedText, now);
  await status(env, {
    outcome: cached === null ? "unavailable" : "fallback",
    checkedAt: now.toISOString(),
    articleCount: 0,
    failureCount: sourceFailures.length,
    sourceFailures
  });
  return cached === null ? { kind: "unavailable" } : { kind: "cached", payload: cachedText! };
}
