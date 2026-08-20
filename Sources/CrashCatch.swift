import Foundation

enum CrashCatch {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            DTLog.line("uncaught \(exception.name.rawValue): \(exception.reason ?? "")")
        }
    }
}
