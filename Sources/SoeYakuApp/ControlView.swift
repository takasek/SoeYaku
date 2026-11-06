import SoeYakuCore
import SwiftUI

private let accent = Color(red: 0.13, green: 0.42, blue: 0.55)

struct ControlView: View {
    @ObservedObject var reader: Reader

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "text.book.closed.fill").font(.system(size: 30)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SoeYaku").font(.title.bold())
                    Text("読んでいる箇所の訳を、隣のウインドウに。").foregroundStyle(.secondary)
                }
                Spacer()
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("文書").font(.headline)
                        Spacer()
                        Button("PDF を開く…") { reader.choosePDF() }.disabled(reader.translating)
                        Button("プレビューで開く") { reader.openInPreview() }.disabled(reader.documentURL == nil)
                    }
                    if let document = reader.document {
                        Text(document.title).lineLimit(1).truncationMode(.middle)
                        Text("\(document.sentences.count) 文・翻訳済み \(reader.translatedCount) 文")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("テキスト層のある英語の PDF を選び、同じファイルをプレビューで開いてください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(6)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("全文翻訳").font(.headline)
                        Spacer()
                        Text(reader.model?.lastPathComponent ?? "モデル未選択").lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("モデル…") { reader.chooseModel() }.disabled(reader.translating || reader.loading)
                    }
                    if let progress = reader.progress {
                        ProgressView(value: Double(progress.done + progress.failed), total: Double(max(progress.total, 1)))
                        Text("\(progress.done) / \(progress.total) 文" + (progress.failed > 0 ? "・失敗 \(progress.failed) 文" : ""))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("訳は文書ごとに保存し、同じ文は訳し直しません。").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if reader.translating {
                            Button("中断") { reader.cancelTranslation() }
                        } else {
                            Button("全文を翻訳") { reader.translateAll() }
                                .buttonStyle(.borderedProminent).tint(accent).disabled(reader.document == nil)
                        }
                    }
                }.padding(6)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("用語集").font(.headline)
                    HStack {
                        Button("共通の用語集…") { reader.openCommonGlossary() }
                        Button("この文書の用語集…") { reader.openDocumentGlossary() }.disabled(reader.document == nil)
                        Spacer()
                        Button("Kikiyaku 用にコピー") { reader.copyGlossaryForKikiyaku() }.disabled(reader.document == nil)
                    }
                    Text("1行に「原語 = 訳語」または「原語<TAB>訳語」。文書の用語集が共通の用語集より優先されます。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }.disabled(reader.translating)
            HStack {
                Image(systemName: "textformat.size").accessibilityLabel("訳文の文字サイズ")
                Slider(value: $reader.fontSize, in: 12...40, step: 1)
                Text("\(Int(reader.fontSize)) pt").monospacedDigit().frame(width: 44)
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                if reader.translating { ProgressView().controlSize(.small) }
                else { Image(systemName: reader.following ? "dot.viewfinder" : "info.circle").foregroundStyle(accent) }
                Text(reader.status).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            HStack {
                Text("画面の文字は現在地を探すためだけに読み、保存しません。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("訳文ウインドウ") { reader.showPanel() }.disabled(reader.document == nil)
                Button(reader.following ? "追従を止める" : "プレビューに追従") { reader.toggleFollowing() }
                    .buttonStyle(.borderedProminent).tint(reader.following ? .gray : accent).disabled(reader.document == nil)
            }
        }
        .padding(22).frame(minWidth: 560, idealWidth: 580, alignment: .topLeading)
    }
}
