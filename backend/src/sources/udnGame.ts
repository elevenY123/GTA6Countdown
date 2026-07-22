import { createJSONLDAdapter } from "./jsonLDAdapter";
export const udnGameAdapter = createJSONLDAdapter({ id: "udn-game", kind: "media", sourceName: "联合新闻网游戏角落", url: "https://game.udn.com/search/word/2/GTA6", baseURL: "https://game.udn.com/", trustedHosts: ["udn.com"], imageHosts: ["udn.com", "udn.com.tw"], articlePathPattern: /^\/game\/story\/\d+\/\d+$/u });
