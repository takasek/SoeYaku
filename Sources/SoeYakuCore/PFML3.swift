import Foundation

enum PFML3 {
    static func prompt(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) -> String {
        let input = "<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>"
        let output = "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:msg|>"
        func literal(_ text: String) -> String { text.replacingOccurrences(of: "<|", with: "＜|") }

        var prompt = "<|plamo:tag|>dataset<|plamo:msg|>translation"
        if !context.isEmpty { prompt += "<|plamo:tag|>context<|plamo:msg|>" + literal(context) }
        for pair in history {
            prompt += input + literal(pair.source) + output + literal(pair.translation)
        }
        let matches = glossary.matches(in: source)
        if !matches.isEmpty {
            prompt += "<|plamo:tag|>glossary"
            for term in matches {
                prompt += "<|plamo:index|>" + literal(term.source) + "<|plamo:item|>" + literal(term.target)
            }
        }
        return prompt + input + literal(source) + output
    }
}
