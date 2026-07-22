import { describe, expect, it, vi } from "vitest";
import type { SourceArticle } from "../src/domain/article";
import { aggregateAndStore, LIVE_SOURCE_ADAPTERS, type WorkerEnv } from "../src/aggregate";
import worker, { createWorker } from "../src/index";

class MemoryKV {
  readonly values = new Map<string, string>();
  readonly failGets = new Set<string>();
  readonly failPuts = new Set<string>();

  async get(key: string): Promise<string | null> {
    if (this.failGets.has(key)) throw new Error(`get failed: ${key}`);
    return this.values.get(key) ?? null;
  }

  async put(key: string, value: string): Promise<void> {
    if (this.failPuts.has(key)) throw new Error(`put failed: ${key}`);
    this.values.set(key, value);
  }
}

function sourceArticle(id = "one"): SourceArticle {
  return {
    id,
    title: "GTA VI 第二支预告片公布",
    summary: "新预告展示了罪恶城与两位主角。",
    sourceName: "游民星空",
    sourceURL: `https://www.gamersky.com/news/260720/${id}.shtml`,
    publishedAt: "2026-07-20T12:00:00Z",
    imageURL: "https://img1.gamersky.com/cover.jpg",
    adapter: { id: "gamersky", kind: "media" },
    claimedCredibility: "official"
  };
}

function env(kv = new MemoryKV()): WorkerEnv {
  return { NEWS_KV: kv };
}

function validPayload(updatedAt = "2026-07-20T13:00:00.000Z"): string {
  return JSON.stringify({
    schemaVersion: 1,
    updatedAt,
    remoteConfig: {
      releaseDate: "2026-11-19",
      releaseTimeMode: "localMidnight",
      milestoneMessages: { "1": "明天见。" },
      pinnedOfficialArticleID: null,
      lastUpdatedAt: updatedAt,
      schemaVersion: 1
    },
    articles: [{
      id: "v1|9:gamersky|3:one|https://www.gamersky.com/news/260720/one.shtml",
      title: "GTA VI 第二支预告片公布",
      summary: "新预告展示了罪恶城与两位主角。",
      sourceName: "游民星空",
      sourceURL: "https://www.gamersky.com/news/260720/one.shtml",
      publishedAt: "2026-07-20T12:00:00.000Z",
      imageURL: "https://img1.gamersky.com/cover.jpg",
      credibility: "media",
      isOfficial: false,
      isPinned: false,
      relatedSourceCount: 0,
      canonicalTopicKey: "gtavi-第二支预告片公布"
    }]
  });
}

describe("scheduled aggregation", () => {
  it("enables only the two adapters with complete live list/detail evidence", () => {
    expect(LIVE_SOURCE_ADAPTERS.map((adapter) => adapter.id)).toEqual(["gamersky", "mydrivers"]);
  });

  it("stores a Swift-compatible payload after partial source failure", async () => {
    const bindings = env();
    const result = await aggregateAndStore(bindings, {
      now: () => new Date("2026-07-20T13:00:00Z"),
      runAdapters: vi.fn().mockResolvedValue({
        articles: [sourceArticle()],
        failures: [{ sourceID: "3dm", stage: "http", reason: "HTTP 403" }]
      })
    });

    expect(result.kind).toBe("fresh");
    const response = await createWorker({ now: () => new Date("2026-07-20T13:30:00Z") })
      .fetch(new Request("https://worker.test/v1/feed"), bindings);
    expect(response.status).toBe(200);
    const payload = await response.json() as Record<string, any>;
    expect(payload).toMatchObject({
      schemaVersion: 1,
      updatedAt: "2026-07-20T13:00:00.000Z",
      remoteConfig: {
        releaseDate: "2026-11-19",
        releaseTimeMode: "localMidnight",
        schemaVersion: 1,
        lastUpdatedAt: "2026-07-20T13:00:00.000Z"
      }
    });
    expect(payload.articles).toHaveLength(2);
    expect(payload.articles.every((article: any) => !("attributedAdapterID" in article))).toBe(true);
    expect(payload.articles.every((article: any) => !("explicitTopicKey" in article))).toBe(true);
    expect(payload.articles.some((article: any) => article.credibility === "media")).toBe(true);
    expect(payload.articles.filter((article: any) => article.isPinned)).toHaveLength(1);
  });

  it("falls back to the most recent payload when every source fails", async () => {
    const bindings = env();
    await bindings.NEWS_KV.put("feed:latest", validPayload("2026-07-20T13:00:00.000Z"));
    const result = await aggregateAndStore(bindings, {
      now: () => new Date("2026-07-20T14:00:00Z"),
      runAdapters: vi.fn().mockResolvedValue({
        articles: [],
        failures: [{ sourceID: "gamersky", stage: "timeout", reason: "timeout" }]
      })
    });

    expect(result).toMatchObject({ kind: "cached" });
    expect(JSON.parse((await bindings.NEWS_KV.get("feed:latest"))!)).toMatchObject({ schemaVersion: 1 });
    expect(JSON.parse((await bindings.NEWS_KV.get("fetch:status"))!)).toMatchObject({
      outcome: "fallback",
      articleCount: 0
    });
  });

  it.each([
    ["malformed", "{"],
    ["wrong schema", JSON.stringify({ schemaVersion: 1, updatedAt: "2026-07-20T13:00:00Z", remoteConfig: {}, articles: [] })],
    ["stale", validPayload("2026-07-10T13:00:00.000Z")],
    ["leaked internal field", validPayload().replace('"canonicalTopicKey":', '"attributedAdapterID":"gamersky","canonicalTopicKey":')]
  ])("rejects a %s cached fallback", async (_name, cached) => {
    const bindings = env();
    await bindings.NEWS_KV.put("feed:latest", cached);
    const result = await aggregateAndStore(bindings, {
      now: () => new Date("2026-07-20T14:00:00Z"),
      runAdapters: vi.fn().mockResolvedValue({ articles: [], failures: [] })
    });
    expect(result.kind).toBe("unavailable");
  });

  it("uses defaults when optional config read fails and ignores status write failure", async () => {
    const kv = new MemoryKV();
    kv.failGets.add("config:remote");
    kv.failPuts.add("fetch:status");
    const result = await aggregateAndStore(env(kv), {
      now: () => new Date("2026-07-20T13:00:00Z"),
      runAdapters: vi.fn().mockResolvedValue({ articles: [sourceArticle()], failures: [] })
    });
    expect(result.kind).toBe("fresh");
    expect(JSON.parse(kv.values.get("feed:latest")!).remoteConfig.releaseDate).toBe("2026-11-19");
  });

  it("rejects the aggregation when the critical feed write fails", async () => {
    const kv = new MemoryKV();
    kv.failPuts.add("feed:latest");
    await expect(aggregateAndStore(env(kv), {
      runAdapters: vi.fn().mockResolvedValue({ articles: [sourceArticle()], failures: [] })
    })).rejects.toThrow("put failed: feed:latest");
  });

  it("applies a validated remote release date while preserving the Swift config shape", async () => {
    const bindings = env();
    await bindings.NEWS_KV.put("config:remote", JSON.stringify({
      releaseDate: "2026-12-01",
      milestoneMessages: { "1": "明天见。", invalid: "忽略" },
      schemaVersion: 99,
      releaseTimeMode: "utc"
    }));
    await aggregateAndStore(bindings, {
      now: () => new Date("2026-07-20T13:00:00Z"),
      runAdapters: vi.fn().mockResolvedValue({ articles: [sourceArticle()], failures: [] })
    });
    const payload = JSON.parse((await bindings.NEWS_KV.get("feed:latest"))!);
    expect(payload.remoteConfig).toMatchObject({
      releaseDate: "2026-12-01",
      releaseTimeMode: "localMidnight",
      milestoneMessages: { "1": "明天见。" },
      lastUpdatedAt: "2026-07-20T13:00:00.000Z",
      schemaVersion: 1
    });
    expect(payload.remoteConfig.pinnedOfficialArticleID).toEqual(expect.any(String));
  });

  it("adds the audited current official record and pins it exactly once", async () => {
    const bindings = env();
    await aggregateAndStore(bindings, {
      runAdapters: vi.fn().mockResolvedValue({
        articles: [sourceArticle()],
        failures: []
      })
    });
    const payload = JSON.parse((await bindings.NEWS_KV.get("feed:latest"))!);
    const pinned = payload.articles.filter((article: any) => article.isPinned);
    expect(pinned).toHaveLength(1);
    expect(pinned[0]).toMatchObject({
      title: "6月25日Grand Theft Auto VI开启预购",
      summary: "Rockstar Games 宣布《Grand Theft Auto VI》现已开启全球预购，并介绍版本、预载与奖励安排。",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/5171972o3ak5oa/pre-order-grand-theft-auto-vi-on-june-25",
      publishedAt: "2026-06-24T12:00:00.000Z",
      isOfficial: true,
      credibility: "official"
    });
    expect(payload.remoteConfig.pinnedOfficialArticleID).toBe(pinned[0].id);
  });

  it.each([
    ["spoofed source", { title: "GTA VI 官方消息", summary: "这是足够长的中文官方消息摘要。", sourceURL: "https://www.rockstargames.com.evil.example/zh/newswire/article/x/y", publishedAt: "2026-07-20T12:00:00Z", imageURL: null }],
    ["identity injection", { title: "GTA VI 官方消息", summary: "这是足够长的中文官方消息摘要。", sourceURL: "https://www.rockstargames.com/zh/newswire/article/x/y", publishedAt: "2026-07-20T12:00:00Z", imageURL: null, adapter: { id: "evil" } }],
    ["older announcement", { title: "GTA VI 较早官方消息", summary: "这是已经被新公告取代的较早官方消息。", sourceURL: "https://www.rockstargames.com/zh/newswire/article/old/old-update", publishedAt: "2026-06-01T12:00:00Z", imageURL: null }],
    ["broken JSON", null]
  ])("falls back to the audited official record for a %s curated override", async (_name, override) => {
    const bindings = env();
    await bindings.NEWS_KV.put("official:curated", override === null ? "{" : JSON.stringify(override));
    await aggregateAndStore(bindings, {
      runAdapters: vi.fn().mockResolvedValue({ articles: [sourceArticle()], failures: [] })
    });
    const payload = JSON.parse((await bindings.NEWS_KV.get("feed:latest"))!);
    expect(payload.articles.find((article: any) => article.isPinned).sourceURL)
      .toContain("/5171972o3ak5oa/");
  });

  it("accepts a bounded private curated override while forcing official identity", async () => {
    const bindings = env();
    await bindings.NEWS_KV.put("official:curated", JSON.stringify({
      title: "Grand Theft Auto VI 官方发布新消息",
      summary: "Rockstar Games 官方公布了 GTA VI 的最新预购安排。",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/verified/new-update",
      publishedAt: "2026-07-20T12:00:00Z",
      imageURL: null
    }));
    await aggregateAndStore(bindings, {
      runAdapters: vi.fn().mockResolvedValue({ articles: [sourceArticle()], failures: [] })
    });
    const payload = JSON.parse((await bindings.NEWS_KV.get("feed:latest"))!);
    expect(payload.articles.find((article: any) => article.isPinned)).toMatchObject({
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/verified/new-update",
      isOfficial: true,
      credibility: "official"
    });
  });

  it("trims and bounds remote milestones and rejects controls and unreasonable release years", async () => {
    const bindings = env();
    const messages: Record<string, string> = { " 1 ": "  明天见。  ", "2": "坏\u0000消息" };
    for (let day = 3; day <= 45; day += 1) messages[String(day)] = `第${day}天`;
    await bindings.NEWS_KV.put("config:remote", JSON.stringify({
      releaseDate: "2099-01-01",
      milestoneMessages: messages
    }));
    await aggregateAndStore(bindings, {
      now: () => new Date("2026-07-20T13:00:00Z"),
      runAdapters: vi.fn().mockResolvedValue({ articles: [sourceArticle()], failures: [] })
    });
    const config = JSON.parse((await bindings.NEWS_KV.get("feed:latest"))!).remoteConfig;
    expect(config.releaseDate).toBe("2026-11-19");
    expect(config.milestoneMessages["1"]).toBe("明天见。");
    expect(config.milestoneMessages["2"]).toBeUndefined();
    expect(Object.keys(config.milestoneMessages).length).toBeLessThanOrEqual(32);
    expect(JSON.stringify(config.milestoneMessages)).not.toContain("\\u0000");
  });

  it("reports unavailable without cache when every source fails", async () => {
    const bindings = env();
    const result = await aggregateAndStore(bindings, {
      runAdapters: vi.fn().mockResolvedValue({ articles: [], failures: [] })
    });
    expect(result.kind).toBe("unavailable");
    expect((await worker.fetch(new Request("https://worker.test/v1/feed"), bindings)).status).toBe(503);
  });

  it("enforces one total batch deadline", async () => {
    const bindings = env();
    let observedSignal: AbortSignal | undefined;
    const started = Date.now();
    const result = await aggregateAndStore(bindings, {
      deadlineMs: 20,
      runAdapters: (_adapters, options) => {
        observedSignal = options?.signal;
        return new Promise((resolve) => options?.signal?.addEventListener("abort", () => {
          resolve({ articles: [], failures: [] });
        }, { once: true }));
      }
    });
    expect(Date.now() - started).toBeLessThan(500);
    expect(observedSignal?.aborted).toBe(true);
    expect(result.kind).toBe("unavailable");
  });
});

describe("Worker read API", () => {
  it("delegates scheduled events to aggregation through waitUntil", async () => {
    const bindings = env();
    const aggregate = vi.fn().mockResolvedValue({ kind: "unavailable" as const });
    const scheduledWorker = createWorker({ aggregate });
    let task: Promise<unknown> | undefined;
    scheduledWorker.scheduled({}, bindings, { waitUntil(value) { task = value; } });
    expect(task).toBeInstanceOf(Promise);
    await task;
    expect(aggregate).toHaveBeenCalledWith(bindings);
  });

  it("returns ETag and honors If-None-Match with a bodyless 304", async () => {
    const bindings = env();
    await bindings.NEWS_KV.put("feed:latest", validPayload());
    const datedWorker = createWorker({ now: () => new Date("2026-07-20T13:30:00Z") });
    const first = await datedWorker.fetch(new Request("https://worker.test/v1/feed"), bindings);
    const etag = first.headers.get("etag");
    expect(etag).toMatch(/^"[a-f0-9]{64}"$/);
    const cached = await datedWorker.fetch(new Request("https://worker.test/v1/feed", {
      headers: { "If-None-Match": etag! }
    }), bindings);
    expect(cached.status).toBe(304);
    expect(await cached.text()).toBe("");
  });

  it.each(["*", "W/ETAG"])('honors If-None-Match value %s using weak comparison', async (value) => {
    const bindings = env();
    await bindings.NEWS_KV.put("feed:latest", validPayload());
    const datedWorker = createWorker({ now: () => new Date("2026-07-20T13:30:00Z") });
    const first = await datedWorker.fetch(new Request("https://worker.test/v1/feed"), bindings);
    const etag = first.headers.get("etag")!;
    const header = value === "W/ETAG" ? `W/${etag}` : value;
    expect((await datedWorker.fetch(new Request("https://worker.test/v1/feed", {
      headers: { "If-None-Match": header }
    }), bindings)).status).toBe(304);
  });

  it.each([
    ["malformed", "{"],
    ["stale", validPayload("2026-07-01T13:00:00.000Z")],
    ["oversized", " ".repeat(1_000_001)],
    ["bad article", validPayload().replace('"credibility":"media"', '"credibility":"official"')]
  ])("returns stable no-store 503 for a %s feed", async (_name, stored) => {
    const bindings = env();
    await bindings.NEWS_KV.put("feed:latest", stored);
    const response = await createWorker({ now: () => new Date("2026-07-20T13:30:00Z") })
      .fetch(new Request("https://worker.test/v1/feed"), bindings);
    expect(response.status).toBe(503);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({ error: "feed_unavailable" });
  });

  it.each([
    validPayload().replace("2026-07-20T12:00:00.000Z", "2026-02-30T12:00:00.000Z"),
    validPayload().replace("2026-07-20T12:00:00.000Z", "2026-07-20T24:00:00.000Z"),
    validPayload().replace("2026-07-20T13:00:00.000Z", "2026-07-20T13:00:00")
  ])("rejects a non-strict API date", async (stored) => {
    const bindings = env();
    await bindings.NEWS_KV.put("feed:latest", stored);
    expect((await createWorker({ now: () => new Date("2026-07-20T13:30:00Z") })
      .fetch(new Request("https://worker.test/v1/feed"), bindings)).status).toBe(503);
  });

  it("returns stable 503 when KV feed read throws", async () => {
    const kv = new MemoryKV();
    kv.failGets.add("feed:latest");
    const response = await worker.fetch(new Request("https://worker.test/v1/feed"), env(kv));
    expect(response.status).toBe(503);
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("serves read-only health state without exposing request identifiers", async () => {
    const kv = new MemoryKV();
    const bindings = env(kv);
    await bindings.NEWS_KV.put("fetch:status", JSON.stringify({ outcome: "success", articleCount: 4 }));
    const response = await worker.fetch(new Request("https://worker.test/health?device_id=secret", {
      headers: { "User-Agent": "private-device" }
    }), bindings);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, outcome: "success", articleCount: 4 });
    expect([...kv.values.values()].join(" ")).not.toContain("secret");
    expect([...kv.values.values()].join(" ")).not.toContain("private-device");
  });

  it("rejects mutations and unknown paths", async () => {
    const bindings = env();
    expect((await worker.fetch(new Request("https://worker.test/v1/feed", { method: "POST" }), bindings)).status).toBe(405);
    expect((await worker.fetch(new Request("https://worker.test/unknown"), bindings)).status).toBe(404);
  });
});
