export const SCHEMA_VERSION = 1;

export interface WorkerRemoteConfig {
  readonly releaseDate: string;
  readonly releaseTimeMode: "localMidnight";
  readonly milestoneMessages: Readonly<Record<string, string>>;
  readonly pinnedOfficialArticleID: string | null;
  readonly lastUpdatedAt: string;
  readonly schemaVersion: number;
}

const MILESTONE_MESSAGES: Readonly<Record<string, string>> = Object.freeze({
  "100": "百日倒计时，罪恶城的霓虹已经亮起。",
  "50": "五十天，再等等，新的旅程就要开始。",
  "20": "二十天，行李可以慢慢收拾了。",
  "10": "十天！倒计时正式进入个位数前夜。",
  "7": "一周后，欢迎回到罪恶城。",
  "6": "六天，霓虹与海风越来越近。",
  "5": "五天，快了，真的快了。",
  "4": "四天，最后一个周末都显得漫长。",
  "3": "三天，准备好踏上莱昂尼达了吗？",
  "2": "两天，故事即将揭幕。",
  "1": "明天见，罪恶城。",
  "0": "今天发售！欢迎来到莱昂尼达。"
});

export function defaultRemoteConfig(now: Date, pinnedOfficialArticleID: string | null = null): WorkerRemoteConfig {
  return {
    releaseDate: "2026-11-19",
    releaseTimeMode: "localMidnight",
    milestoneMessages: MILESTONE_MESSAGES,
    pinnedOfficialArticleID,
    lastUpdatedAt: now.toISOString(),
    schemaVersion: SCHEMA_VERSION
  };
}

function validReleaseDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/u.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (year < 2025 || year > 2035) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

/** Applies only the remotely editable values while retaining the API schema. */
export function resolveRemoteConfig(value: unknown, now: Date, pinnedOfficialArticleID: string | null): WorkerRemoteConfig {
  const fallback = defaultRemoteConfig(now, pinnedOfficialArticleID);
  if (!value || typeof value !== "object" || Array.isArray(value)) return fallback;
  const candidate = value as Record<string, unknown>;
  const milestoneMessages: Record<string, string> = {};
  let milestoneBytes = 0;
  if (candidate.milestoneMessages && typeof candidate.milestoneMessages === "object"
    && !Array.isArray(candidate.milestoneMessages)) {
    const entries = Object.entries(candidate.milestoneMessages as Record<string, unknown>)
      .map(([key, message]) => [key.trim(), typeof message === "string" ? message.trim() : ""] as const)
      .sort(([left], [right]) => Number(left) - Number(right) || left.localeCompare(right));
    for (const [trimmedKey, trimmedMessage] of entries) {
      const entryBytes = new TextEncoder().encode(trimmedKey).byteLength + new TextEncoder().encode(trimmedMessage).byteLength;
      if (Object.keys(milestoneMessages).length < 32 && milestoneMessages[trimmedKey] === undefined
        && /^\d{1,4}$/u.test(trimmedKey) && Number(trimmedKey) <= 3650
        && trimmedMessage.length > 0 && trimmedMessage.length <= 120
        && !/[\u0000-\u001f\u007f-\u009f]/u.test(trimmedMessage)
        && milestoneBytes + entryBytes <= 4_096) {
        milestoneMessages[trimmedKey] = trimmedMessage;
        milestoneBytes += entryBytes;
      }
    }
  }
  return {
    ...fallback,
    releaseDate: validReleaseDate(candidate.releaseDate) ? candidate.releaseDate : fallback.releaseDate,
    milestoneMessages: Object.keys(milestoneMessages).length > 0 ? milestoneMessages : fallback.milestoneMessages
  };
}
