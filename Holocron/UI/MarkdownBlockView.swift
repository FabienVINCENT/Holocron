import SwiftUI

/// Lightweight block-level Markdown renderer for plans and messages.
/// Handles headings, bullet/numbered lists, fenced code blocks; everything
/// else goes through AttributedString's inline Markdown (bold, code, links).
struct MarkdownBlockView: View {
    let markdown: String

    private enum Block {
        case heading(String, level: Int)
        case bullet(String)
        case code(String)
        case paragraph(String)
    }

    var body: some View {
        let blocks = Self.parse(markdown)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let text, let level):
            Text(inline(text))
                .font(.system(size: level <= 2 ? 13 : 11.5, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 5) {
                Text("•")
                    .foregroundStyle(Theme.textTertiary)
                Text(inline(text))
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.system(size: 10.5))
        case .code(let code):
            Text(code)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("#") {
                flushParagraph()
                let level = line.prefix(while: { $0 == "#" }).count
                blocks.append(.heading(
                    line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces),
                    level: level
                ))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                flushParagraph()
                blocks.append(.bullet(String(line[range.upperBound...])))
            } else {
                paragraph.append(line)
            }
        }
        if inCode, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }
}
