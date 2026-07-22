export type AdapterKind = "officialCandidate" | "media" | "community";

export interface SourceAdapterIdentity {
  readonly id: string;
  readonly kind: AdapterKind;
}

export interface OriginalSource {
  readonly sourceName: string;
  readonly sourceURL: string;
  readonly adapter: SourceAdapterIdentity;
}

/** Adapter output. Trust fields are deliberately absent; credibility is derived. */
export interface SourceArticle {
  readonly id: string;
  readonly title: string;
  readonly summary: string;
  readonly sourceName: string;
  readonly sourceURL: string;
  readonly publishedAt: string;
  readonly imageURL?: string | null;
  readonly adapter: SourceAdapterIdentity;
  readonly upstreamTopicKey?: string | null;
  readonly originalSource?: OriginalSource | null;
  readonly isLeak?: boolean;
  readonly isPinned?: boolean;
  readonly relatedSourceCount?: number;
  /** Untrusted compatibility input. Domain classification always ignores it. */
  readonly claimedCredibility?: "official" | "media" | "unverified";
}

export type Credibility = "official" | "media" | "unverified";

/** JSON-compatible shape consumed by the Swift NewsArticle decoder. */
export interface NormalizedArticle {
  readonly id: string;
  readonly title: string;
  readonly summary: string;
  readonly sourceName: string;
  readonly sourceURL: string;
  readonly publishedAt: string;
  readonly imageURL: string | null;
  readonly credibility: Credibility;
  readonly isOfficial: boolean;
  readonly isPinned: boolean;
  readonly relatedSourceCount: number;
  readonly canonicalTopicKey: string;
}

/** Internal aggregation metadata. Strip it before emitting the Worker JSON API. */
export interface PipelineArticle extends NormalizedArticle {
  readonly attributedAdapterID: string;
  readonly explicitTopicKey: string | null;
}

export function toNewsArticle(article: PipelineArticle): NormalizedArticle {
  return {
    id: article.id,
    title: article.title,
    summary: article.summary,
    sourceName: article.sourceName,
    sourceURL: article.sourceURL,
    publishedAt: article.publishedAt,
    imageURL: article.imageURL,
    credibility: article.credibility,
    isOfficial: article.isOfficial,
    isPinned: article.isPinned,
    relatedSourceCount: article.relatedSourceCount,
    canonicalTopicKey: article.canonicalTopicKey
  };
}
