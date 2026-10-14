import Foundation

let logFilePath = "/tmp/alttab-lite.log"

private let logHandle: FileHandle? = {
    FileManager.default.createFile(atPath: logFilePath, contents: nil)
    return FileHandle(forWritingAtPath: logFilePath)
}()

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

func log(_ message: String) {
    let line = "[\(logDateFormatter.string(from: Date()))] \(message)\n"
    let data = Data(line.utf8)
    try? FileHandle.standardError.write(contentsOf: data)
    try? logHandle?.write(contentsOf: data)
}
