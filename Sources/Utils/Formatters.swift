import Foundation

// MARK: - Double 时间格式化扩展

extension Double {
    /// 将秒数格式化为时间字符串 (MM:SS 或 HH:MM:SS)
    /// - Parameter fallback: 无效值时的返回字符串，默认为 "00:00"
    /// - Returns: 格式化的时间字符串
    func timeFormatted(fallback: String = "00:00") -> String {
        guard isFinite && self >= 0 else { return fallback }
        
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// 将秒数格式化为简短时间字符串 (MM:SS)，不显示小时
    /// - Returns: 格式化的时间字符串，无效值返回 "--:--"
    func shortTimeFormatted() -> String {
        guard isFinite && self >= 0 else { return "--:--" }
        
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - TimeInterval 别名

extension TimeInterval {
    /// TimeInterval 是 Double 的别名，此扩展提供相同的时间格式化功能
    var timeFormatted: String {
        Double(self).timeFormatted()
    }
}
