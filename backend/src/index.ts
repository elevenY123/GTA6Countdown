import { aggregateAndStore, FEED_KEY, STATUS_KEY, type WorkerEnv } from "./aggregate";
import { validateStoredFeed } from "./feedValidation";

interface ExecutionContextLike {
  waitUntil(promise: Promise<unknown>): void;
}

function json(value: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(JSON.stringify(value), { ...init, headers });
}

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function feed(request: Request, env: WorkerEnv, now: Date): Promise<Response> {
  let payload: string | null = null;
  try { payload = await env.NEWS_KV.get(FEED_KEY); } catch { /* stable unavailable response below */ }
  if (payload === null || validateStoredFeed(payload, now) === null) {
    return json({ error: "feed_unavailable" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
  const etag = `"${await sha256(payload)}"`;
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "public, max-age=300, stale-if-error=86400",
    "ETag": etag,
    "X-Content-Type-Options": "nosniff"
  });
  const noneMatch = request.headers.get("If-None-Match")?.split(",").map((item) => item.trim()) ?? [];
  const opaque = (value: string) => value.replace(/^W\//iu, "");
  if (noneMatch.includes("*") || noneMatch.some((candidate) => opaque(candidate) === opaque(etag))) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(payload, { status: 200, headers });
}

async function health(env: WorkerEnv): Promise<Response> {
  let stored: unknown = null;
  try { stored = JSON.parse(await env.NEWS_KV.get(STATUS_KEY) ?? "null"); } catch { /* invalid or unavailable status */ }
  const record = stored && typeof stored === "object" ? stored as Record<string, unknown> : {};
  const outcome = ["success", "fallback", "unavailable"].includes(String(record.outcome))
    ? String(record.outcome)
    : "unavailable";
  const articleCount = Number.isSafeInteger(record.articleCount) && Number(record.articleCount) >= 0
    ? Number(record.articleCount)
    : 0;
  const ok = outcome === "success" || outcome === "fallback";
  return json({ ok, outcome, articleCount }, {
    status: ok ? 200 : 503,
    headers: { "Cache-Control": "no-store" }
  });
}

interface WorkerDependencies {
  readonly aggregate?: typeof aggregateAndStore;
  readonly now?: () => Date;
}

export function createWorker(dependencies: WorkerDependencies = {}) {
  const aggregate = dependencies.aggregate ?? aggregateAndStore;
  const now = dependencies.now ?? (() => new Date());
  return {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    if (request.method !== "GET") {
      return json({ error: "method_not_allowed" }, { status: 405, headers: { Allow: "GET" } });
    }
    const pathname = new URL(request.url).pathname;
    if (pathname === "/v1/feed") return feed(request, env, now());
    if (pathname === "/health") return health(env);
    return json({ error: "not_found" }, { status: 404 });
  },

  scheduled(_event: unknown, env: WorkerEnv, context: ExecutionContextLike): void {
    context.waitUntil(aggregate(env));
  }
  };
}

const worker = createWorker();

export default worker;
