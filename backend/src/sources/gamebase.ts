import { createJSONLDAdapter } from "./jsonLDAdapter";
export const gamebaseAdapter = createJSONLDAdapter({ id: "gamebase", kind: "media", sourceName: "Gamebase", url: "https://news.gamebase.com.tw/search?keyword=GTA6", baseURL: "https://news.gamebase.com.tw/", trustedHosts: ["gamebase.com.tw"], imageHosts: ["gamebase.com.tw"], articlePathPattern: /^\/news\/detail\/\d+$/u });
