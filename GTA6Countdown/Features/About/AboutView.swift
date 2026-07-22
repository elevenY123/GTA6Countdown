import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("关于本应用") {
                    Label("非官方 GTA VI 倒计时与中文资讯工具", systemImage: "info.circle.fill")
                    Text("本应用由爱好者独立制作，与 Rockstar Games、Take-Two Interactive 或其关联公司没有从属、赞助或授权关系，也不代表任何官方立场。")
                }

                Section("商标与素材") {
                    Text("Grand Theft Auto、GTA、GTA VI、Rockstar Games 及相关标志和美术素材的商标与著作权归各自权利人所有。应用中的首页人物美术来自 Rockstar Games 官方公开页面，仅用于资讯识别与介绍。")
                    Link("查看 Rockstar Games 官方页面", destination: Self.rockstarURL)
                }

                Section("新闻来源") {
                    Text("新闻列表聚合 Rockstar Games 中文 Newswire 及已标明来源的中文游戏媒体，只展示标题、短导语、来源和原文链接，不转载新闻全文。来源与可信度会显示在每条内容旁。")
                }

                Section("社区预测地图") {
                    Text("地图由 MyGTA 社区依据公开资料分析绘制，是玩家预测内容，并非 Rockstar Games 官方最终地图。")
                    Link("访问 MyGTA 社区预测地图", destination: Self.myGTAURL)
                }

                Section("隐私") {
                    Text("本应用无需账号，不收集用户设备标识，不建立个人画像。服务器只提供公开新闻数据；应用会在本地缓存新闻和图片，以便断网时继续浏览。")
                    Text("浏览新闻列表时，应用会直接连接新闻来源站加载封面图片，无需点击原文；来源站可能因此收到你的 IP 地址、User-Agent 等常规网络请求信息。打开新闻原文或地图时，目标网站还可能适用其自身的隐私政策。")
                }
            }
            .navigationTitle("关于与说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private static let rockstarURL = URL(string: "https://www.rockstargames.com/VI")!
    private static let myGTAURL = URL(string: "https://map.mygta.online")!
}
