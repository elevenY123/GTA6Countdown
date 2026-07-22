import Foundation

enum MilestoneMessage {
    static func text(for state: CountdownState) -> String {
        if state.isReleased {
            return "等待结束。欢迎来到莱昂尼达。"
        }

        switch state.calendarDaysRemaining {
        case 100:
            return "最后一百天，正式开始。"
        case 50:
            return "五十天后，阳光之州见。"
        case 20:
            return "漫长等待，只剩二十天。"
        case 10:
            return "两只手，已经数得过来了。"
        case 7:
            return "最后一周，准备前往罪恶城。"
        case 6:
            return "数字终于对上了：VI 天。"
        case 5:
            return "等了这么多年，只剩五天。"
        case 4:
            return "四天后，莱昂尼达见。"
        case 3:
            return "三天。真的快了。"
        case 2:
            return "后天，杰森与露西亚登场。"
        case 1:
            return "明天。今晚大概睡不着了。"
        default:
            return "快了，快了。罪恶城正在靠近。"
        }
    }
}
