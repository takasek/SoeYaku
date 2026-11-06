import Foundation
import SoeYakuCLIKit
import SoeYakuCore

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

do {
    switch try Command.parse(Array(CommandLine.arguments.dropFirst())) {
    case .extract(let file):
        try CLI.extractLines(file: URL(fileURLWithPath: file)).forEach { print($0) }
    case .translate(let options):
        let translator = try LocalTranslator(port: options.port, apiKey: options.apiKey)
        let lines = try await CLI.translateLines(options, translator: translator) { progress in
            printError("\(progress.done)/\(progress.total) failed=\(progress.failed)")
        }
        lines.forEach { print($0) }
    case .locate(let file, let image, let pointer):
        print(try await CLI.locateLine(file: URL(fileURLWithPath: file), image: URL(fileURLWithPath: image), pointer: pointer))
    }
} catch let error as UsageError {
    printError("\(error.message)\n\(Command.usage)")
    exit(2)
} catch {
    printError(error.localizedDescription)
    exit(1)
}
