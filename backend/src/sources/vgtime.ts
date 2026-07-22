import { createJSONLDAdapter } from "./jsonLDAdapter";
export const vgtimeAdapter = createJSONLDAdapter({ id: "vgtime", kind: "media", sourceName: "游戏时光", url: "https://www.vgtime.com/search/list.jhtml?keyword=GTA6", baseURL: "https://www.vgtime.com/", trustedHosts: ["vgtime.com"], imageHosts: ["vgtime.com"], articlePathPattern: /^\/news\/[A-Za-z0-9%+=_-]+$/u });
