import { createJSONLDAdapter } from "./jsonLDAdapter";
export const bahamutAdapter = createJSONLDAdapter({ id: "bahamut-gnn", kind: "media", sourceName: "巴哈姆特 GNN", url: "https://gnn.gamer.com.tw/search.php?keyword=GTA6", baseURL: "https://gnn.gamer.com.tw/", trustedHosts: ["gamer.com.tw"], imageHosts: ["gamer.com.tw", "bahamut.com.tw"], articlePathPattern: /^\/detail\.php\?sn=\d+$/u });
