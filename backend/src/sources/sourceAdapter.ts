import type { AdapterKind, SourceArticle } from "../domain/article";

export type AdapterFailureStage = "fetch" | "http" | "size" | "decode" | "discover" | "parse" | "timeout" | "cancelled";

export interface AdapterFailure {
  readonly sourceID: string;
  readonly stage: AdapterFailureStage;
  readonly reason: string;
}

export type AdapterParseResult =
  | { readonly ok: true; readonly articles: readonly SourceArticle[] }
  | { readonly ok: false; readonly failure: AdapterFailure };

export interface SourceAdapter {
  readonly id: string;
  readonly kind: AdapterKind;
  readonly sourceName: string;
  readonly url: string;
  readonly trustedHosts: readonly string[];
  readonly imageHosts: readonly string[];
  discover(html: string): readonly string[];
  parse(html: string, pageURL?: string): AdapterParseResult;
}

export interface RunnerOptions {
  readonly fetcher?: typeof fetch;
  readonly concurrency?: number;
  readonly timeoutMs?: number;
  readonly maxResponseBytes?: number;
  readonly maxArticlesPerSource?: number;
  readonly signal?: AbortSignal;
}

export interface AdapterBatchResult {
  readonly articles: readonly SourceArticle[];
  readonly failures: readonly AdapterFailure[];
}

const DEFAULT_TIMEOUT_MS = 8_000;
const DEFAULT_MAX_RESPONSE_BYTES = 1_000_000;
const DEFAULT_MAX_ARTICLES = 20;
const DEFAULT_CONCURRENCY = 3;

function failure(sourceID: string, stage: AdapterFailureStage, reason: string): AdapterFailure {
  return { sourceID, stage, reason: reason.slice(0, 240) };
}

function boundedInteger(value: number | undefined, fallback: number, minimum: number, maximum: number): number {
  return value === undefined || !Number.isFinite(value)
    ? fallback
    : Math.min(maximum, Math.max(minimum, Math.trunc(value)));
}

async function responseText(response: Response, maximumBytes: number, sourceID: string): Promise<string> {
  const declaredCharset = response.headers.get("content-type")?.match(/charset\s*=\s*["']?([^;\s"']+)/iu)?.[1]
    ?.toLocaleLowerCase("en-US");
  if (declaredCharset && !["utf-8", "utf8", "us-ascii", "ascii"].includes(declaredCharset)) {
    throw failure(sourceID, "decode", `unsupported response charset: ${declaredCharset}`);
  }
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maximumBytes) {
    throw failure(sourceID, "size", "response Content-Length exceeds configured limit");
  }
  if (!response.body) {
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > maximumBytes) throw failure(sourceID, "size", "response exceeds configured limit");
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      total += next.value.byteLength;
      if (total > maximumBytes) {
        await reader.cancel("response exceeds configured limit");
        throw failure(sourceID, "size", "response exceeds configured limit");
      }
      chunks.push(next.value);
    }
  } catch (error) {
    if (typeof error === "object" && error !== null && "sourceID" in error) throw error;
    throw failure(sourceID, "decode", error instanceof Error ? error.message : "response stream failed");
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const prologue = new TextDecoder("utf-8").decode(bytes.slice(0, 4_096));
  const documentCharset = prologue.match(/<meta\b[^>]*(?:charset\s*=\s*["']?([^\s"'/>;]+)|content\s*=\s*["'][^"']*charset\s*=\s*([^\s"';>]+))/iu);
  const charset = (documentCharset?.[1] ?? documentCharset?.[2])?.toLocaleLowerCase("en-US");
  if (charset && !["utf-8", "utf8", "us-ascii", "ascii"].includes(charset)) {
    throw failure(sourceID, "decode", `unsupported document charset: ${charset}`);
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw failure(sourceID, "decode", "response is not valid UTF-8");
  }
}

async function runOne(adapter: SourceAdapter, options: Required<Pick<RunnerOptions,
  "fetcher" | "timeoutMs" | "maxResponseBytes" | "maxArticlesPerSource">> & Pick<RunnerOptions, "signal">): Promise<AdapterBatchResult> {
  if (options.signal?.aborted) {
    return { articles: [], failures: [failure(adapter.id, "cancelled", "batch cancelled")] };
  }

  const controller = new AbortController();
  let rejectCancellation: ((reason: AdapterFailure) => void) | undefined;
  const cancellation = new Promise<never>((_, reject) => { rejectCancellation = reject; });
  const onExternalAbort = () => {
    controller.abort(options.signal?.reason);
    rejectCancellation?.(failure(adapter.id, "cancelled", "batch cancelled"));
  };
  options.signal?.addEventListener("abort", onExternalAbort, { once: true });
  let timer: ReturnType<typeof setTimeout> | undefined;
  let timedOut = false;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      timedOut = true;
      controller.abort("source timeout");
      reject(failure(adapter.id, "timeout", "source request timed out"));
    }, options.timeoutMs);
  });

  try {
    const trustedURL = (value: string, base?: string): URL => {
      const url = new URL(value, base);
      const trusted = adapter.trustedHosts.some((host) => url.hostname === host || url.hostname.endsWith(`.${host}`));
      if (url.protocol !== "https:" || (url.port !== "" && url.port !== "443") || !trusted || url.username || url.password) {
        throw failure(adapter.id, "fetch", "request left the source trust boundary");
      }
      return url;
    };
    const fetchPage = async (urlValue: string): Promise<string> => {
      let url = trustedURL(urlValue);
      const visited = new Set<string>();
      let response: Response | undefined;
      for (let redirects = 0; redirects <= 3; redirects += 1) {
        if (visited.has(url.href)) throw failure(adapter.id, "fetch", "redirect cycle detected");
        visited.add(url.href);
        response = await Promise.race([
          options.fetcher(url.href, {
            signal: controller.signal,
            headers: { Accept: "text/html,application/ld+json;q=0.9", "User-Agent": "GTA6Countdown/0.1" },
            redirect: "manual"
          }),
          timeout,
          cancellation
        ]);
        if (response.status < 300 || response.status >= 400) break;
        const location = response.headers.get("location");
        if (!location) throw failure(adapter.id, "http", `HTTP ${response.status} without Location`);
        if (redirects === 3) throw failure(adapter.id, "fetch", "too many redirects");
        url = trustedURL(location, url.href);
      }
      if (!response) throw failure(adapter.id, "fetch", "source returned no response");
      if (!response.ok) throw failure(adapter.id, "http", `HTTP ${response.status}`);
      if (response.url) {
        const finalURL = new URL(response.url);
        const trusted = adapter.trustedHosts.some((host) => finalURL.hostname === host || finalURL.hostname.endsWith(`.${host}`));
        if (finalURL.protocol !== "https:" || (finalURL.port !== "" && finalURL.port !== "443") || !trusted || finalURL.username || finalURL.password) {
          throw failure(adapter.id, "fetch", "redirect left the source trust boundary");
        }
      }
      return Promise.race([responseText(response, options.maxResponseBytes, adapter.id), timeout, cancellation]);
    };

    const listing = await fetchPage(adapter.url);
    const detailURLs = adapter.discover(listing).slice(0, options.maxArticlesPerSource);
    if (detailURLs.length === 0) {
      return { articles: [], failures: [failure(adapter.id, "discover", "no trusted article links found")] };
    }
    const articles: SourceArticle[] = [];
    const failures: AdapterFailure[] = [];
    for (const detailURL of detailURLs) {
      try {
        const detail = await fetchPage(detailURL);
        let parsed: AdapterParseResult;
        try {
          parsed = adapter.parse(detail, detailURL);
        } catch (error) {
          failures.push(failure(adapter.id, "parse", error instanceof Error ? error.message : "unexpected parser failure"));
          continue;
        }
        if (parsed.ok) articles.push(...parsed.articles.slice(0, 1));
        else failures.push(parsed.failure);
      } catch (error) {
        const itemFailure = typeof error === "object" && error !== null && "sourceID" in error
          ? error as AdapterFailure
          : failure(adapter.id, timedOut ? "timeout" : "fetch", error instanceof Error ? error.message : "detail fetch failed");
        failures.push(itemFailure);
        if (itemFailure.stage === "timeout" || itemFailure.stage === "cancelled") break;
      }
    }
    return { articles: articles.slice(0, options.maxArticlesPerSource), failures };
  } catch (error) {
    if (typeof error === "object" && error !== null && "sourceID" in error && "stage" in error) {
      return { articles: [], failures: [error as AdapterFailure] };
    }
    const stage: AdapterFailureStage = timedOut ? "timeout" : options.signal?.aborted ? "cancelled" : "fetch";
    return { articles: [], failures: [failure(adapter.id, stage, error instanceof Error ? error.message : stage)] };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    options.signal?.removeEventListener("abort", onExternalAbort);
  }
}

export async function runSourceAdapters(
  adapters: readonly SourceAdapter[],
  options: RunnerOptions = {}
): Promise<AdapterBatchResult> {
  const concurrency = Math.min(adapters.length || 1, boundedInteger(options.concurrency, DEFAULT_CONCURRENCY, 1, 8));
  const resolved = {
    fetcher: options.fetcher ?? fetch,
    timeoutMs: boundedInteger(options.timeoutMs, DEFAULT_TIMEOUT_MS, 1, 60_000),
    maxResponseBytes: boundedInteger(options.maxResponseBytes, DEFAULT_MAX_RESPONSE_BYTES, 1, 5_000_000),
    maxArticlesPerSource: boundedInteger(options.maxArticlesPerSource, DEFAULT_MAX_ARTICLES, 1, 100),
    signal: options.signal
  };
  const results: AdapterBatchResult[] = new Array(adapters.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < adapters.length) {
      const index = nextIndex++;
      results[index] = await runOne(adapters[index], resolved);
    }
  }

  await Promise.all(Array.from({ length: concurrency }, worker));
  return {
    articles: results.flatMap((result) => result.articles),
    failures: results.flatMap((result) => result.failures)
  };
}
