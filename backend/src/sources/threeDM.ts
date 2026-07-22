import { createJSONLDAdapter } from "./jsonLDAdapter";
export const threeDMAdapter = createJSONLDAdapter({ id: "3dm", kind: "media", sourceName: "3DM", url: "https://so.3dmgame.com/?keyword=GTA6&type=7", baseURL: "https://www.3dmgame.com/", trustedHosts: ["3dmgame.com"], imageHosts: ["3dmgame.com"], articlePathPattern: /^\/news\/\d{6}\/\d+\.html$/u });
