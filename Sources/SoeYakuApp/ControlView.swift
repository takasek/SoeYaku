import SoeYakuCore
import SwiftUI

private let accent = Color(red: 0.13, green: 0.42, blue: 0.55)

struct ControlView: View {
    @ObservedObject var reader: Reader
    @ObservedObject private var frames: FrameReader

    init(reader: Reader) { self.reader = reader; frames = reader.frames }

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
            Picker("モード", selection: $reader.mode) {
                ForEach(ReadingMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
                .disabled(reader.translating || reader.loading || frames.running || frames.selecting)
            if reader.mode == .document {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("文書").font(.headline)
                        Spacer()
                        Button("PDF・HTML を開く…") { reader.chooseDocument() }.disabled(reader.translating)
                        Button("URL を開く…") { reader.chooseURL() }.disabled(reader.translating)
                        Button("\(reader.viewerName)で開く") { reader.openInViewer() }.disabled(reader.documentURL == nil)
                    }
                    if reader.isHTML {
                        Picker("ブラウザ", selection: $reader.browserBundleID) {
                            ForEach(reader.browsers) { browser in Text(browser.name).tag(browser.id) }
                        }.frame(maxWidth: 280)
                    }
                    if let document = reader.document {
                        Text(document.title).lineLimit(1).truncationMode(.middle)
                        Text("\(document.sentences.count) 文・翻訳済み \(reader.translatedCount) 文")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("PDF はプレビュー、HTML は選んだブラウザで同じ文書を開いて読みます。")
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
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(reader.mode == .frameText ? "枠内の訳を連続テキストで読む" : "枠の画像と訳を同じ比率で見る").font(.headline)
                        Text(reader.mode == .frameText
                             ? "細長い範囲も選べます。訳は読み順に並び、訳文窓の幅で折り返します。"
                             : "選んだ枠の画像を別窓に複製し、原文の位置へ訳を重ねます。窓の縦横比は枠と揃えます。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(frames.region == nil ? "枠を選ぶ…" : "枠を選び直す…") { frames.chooseRegion() }
                                .disabled(frames.running || frames.selecting)
                            if let region = frames.region {
                                Text("\(Int(region.size.width)) × \(Int(region.size.height))")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack {
                            Text(reader.model?.lastPathComponent ?? "モデル未選択").lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("モデル…") { reader.chooseModel() }.disabled(frames.running || frames.selecting)
                        }
                        HStack {
                            Button("共通の用語集…") { reader.openCommonGlossary() }.disabled(frames.running)
                            Text("用語の変更は停止して再開すると反映します。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(6)
                }
            }
            if reader.mode != .frameImage {
            HStack {
                Image(systemName: "textformat.size").accessibilityLabel("訳文の文字サイズ")
                Slider(value: $reader.fontSize, in: 12...40, step: 1)
                Text("\(Int(reader.fontSize)) pt").monospacedDigit().frame(width: 44)
            }
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                if reader.translating || frames.running { ProgressView().controlSize(.small) }
                else { Image(systemName: reader.following ? "dot.viewfinder" : "info.circle").foregroundStyle(accent) }
                Text(reader.mode == .document ? reader.status : frames.status).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            HStack {
                Text(reader.mode == .document ? "画面の文字は現在地を探すためだけに読み、保存しません。" : "選んだ画面範囲を翻訳します。画像・原文・訳は保存しません。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("訳文ウインドウ") { reader.showPanel() }.disabled(reader.mode == .document ? reader.document == nil : frames.region == nil)
                if reader.mode == .document {
                Button(reader.following ? "追従を止める" : "\(reader.viewerName)に追従") { reader.toggleFollowing() }
                    .buttonStyle(.borderedProminent).tint(reader.following ? .gray : accent).disabled(reader.document == nil)
                } else {
                    Button(frames.running ? "翻訳を止める" : "枠の翻訳を開始") {
                        if frames.running { frames.stop() } else { frames.start(model: reader.model, style: reader.mode) }
                    }.buttonStyle(.borderedProminent).tint(frames.running ? .gray : accent)
                        .disabled(frames.region == nil || frames.selecting)
                }
            }
        }
        .padding(22).frame(minWidth: 560, idealWidth: 580, alignment: .topLeading)
    }
}
