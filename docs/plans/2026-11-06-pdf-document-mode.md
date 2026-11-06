# ドキュメントモード PDF 経路 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 英語の PDF を全文事前翻訳して保存し、「プレビュー」でポインターを置いた文の訳へ別窓の全訳が追従する。

**Architecture:** 純粋なロジック（PDF 抽出・用語集・事前翻訳・現在地照合・座標変換）を `SoeYakuCore` に置き、Swift Testing で検証する。Vision の文字認識は `SoeYakuVision`、llama-server の起動は Local Caption から移植した `SoeYakuRuntime`、画面取得と窓は `SoeYakuApp` が担う。翻訳は llama-server の `/completion` に PFML3 形式で渡す（en→ja 固定、用語は glossary タグ）。

**Tech Stack:** Swift 6.2+、macOS 26+、PDFKit、NaturalLanguage、Vision、ScreenCaptureKit、SwiftUI/AppKit、llama.cpp build 11960、PLaMo 3 Translate 2B GGUF。

**Spec:** `/Users/m5/Documents/Codex/2026-11-06/works/SoeYaku-plan.md` の「最初に作るもの」1〜3 と「用語集と Kikiyaku への連絡」の形式部分。手順4（HTML・枠モード1・枠モード2）はこの計画の対象外。

## Global Constraints

- 翻訳・認識はすべて Mac 内で行い、通信先は 127.0.0.1 の llama-server だけにする。
- 訳文は SoeYaku の専用ウインドウにだけ出す。元アプリの上に描画しない。専用ウインドウは非アクティブ化パネルにし、元アプリのフォーカスを奪わない。
- 原文の座標は列挙順（読み順）の決定にのみ使う。訳文ウインドウは読み順の連続テキストで、窓幅で折り返す。
- 用語集は TSV（`原語<TAB>訳語`）と Kikiyaku 形式（`原語 = 訳語`）の両方を読む。共通辞書の後に文書別辞書を重ね、後の訳語を優先する。書き出しは `原語 = 訳語` の1行1組。
- 一度訳した文は保存し、同じ原文（同じ適用用語・同じモデル）には保存済みの訳を再利用する。同じ箇所に戻ると同じ訳が出ることはこの保存で保証する。
- テストは Swift Testing。TDD（Red→Green→Refactor）で、コミットは RGR サイクルまたは責務単位ごと。

## 未決事項に置いた既定値

- **現在地:** ポインターが対象アプリの最前面ウインドウ内にあり、そのアプリが最前面のときだけ、ポインター直下（または最寄り）の行から文を特定する。それ以外は直前の現在地を保つ。
- **照合不能:** 一致が弱い、または離れた2箇所が同程度に一致して直前位置でも決められないときは `unresolved` を返し、訳文ウインドウは動かさない。
- **採点:** 正答率の分母や文単位の合格基準は決めない。`soeyaku-cli locate` がスクリーンショット1枚ごとに matched/unresolved と文番号を出すので、正解を付けた画像で後から採点できる。

## Review Focus

1. 二段組みのページで、左段の末尾から右段の先頭へ文がまたがる。抽出は左段→右段の順で1文につなぐ。
2. 同じ見出し（例 "Results"）が文書内に複数回出る。照合は前後の行を文脈に使い、それでも決まらなければ直前位置に近い方を選ぶ。
3. ウインドウ上下端で切れた行や、ツールバー・ページ番号など文書にない行が OCR に混じる。一致しない行は無視し、誤った位置へ動かない。
4. 行末ハイフンで分割された語（`transla-` / `tion`）。抽出は結合し、照合も OCR の行をまたいで結合する。
5. 翻訳サーバーが途中で落ちる・1文だけ失敗する。1文の失敗は飛ばして続け、連続失敗で中断する。中断しても訳し終えた分は保存済みで、再開時に再利用される。

---

### Task 1: 用語集・PFML3・翻訳クライアント・事前翻訳（`SoeYakuCore`）

**Files:**
- Create: `Sources/SoeYakuCore/Glossary.swift`, `Sources/SoeYakuCore/PFML3.swift`, `Sources/SoeYakuCore/LocalTranslator.swift`, `Sources/SoeYakuCore/TranslationMemory.swift`, `Sources/SoeYakuCore/Pretranslation.swift`
- Test: `Tests/SoeYakuCoreTests/GlossaryTests.swift`, `Tests/SoeYakuCoreTests/TranslatorTests.swift`, `Tests/SoeYakuCoreTests/PretranslationTests.swift`
- 移植元: `/Users/m5/works/local-caption/Sources/CaptionCore/Translation.swift` と `/Users/m5/works/local-caption/Tests/CaptionCoreTests/TranslationTests.swift`

**Interfaces:**
- Consumes: `Sentence`, `SourceDocument`（`Sources/SoeYakuCore/Document.swift`）
- Produces:
  - `public struct GlossaryTerm: Sendable, Equatable { public let source: String; public let target: String; public func occurs(in text: String) -> Bool }`
  - `public struct Glossary: Sendable, Equatable { public init(); public private(set) var terms: [GlossaryTerm]; public static func parse(_ text: String, name: String) throws -> Glossary; public mutating func overlay(_ other: Glossary); public static func load(_ files: [URL]) throws -> Glossary; public func matches(in text: String) -> [GlossaryTerm]; public func kikiyakuText(appliedTo texts: [String]) -> String }`
  - `public struct TranslationPair: Sendable, Equatable { source, translation }`
  - `public protocol SentenceTranslator: Sendable { func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String }`
  - `public struct LocalTranslator: SentenceTranslator { public init(port: Int, apiKey: String?) throws }`
  - `public struct TranslationMemory: Codable, Sendable, Equatable { public init(); public static func key(source: String, terms: [GlossaryTerm], model: String) -> String; public subscript(key: String) -> String? { get set }; public static func load(from url: URL) throws -> TranslationMemory; public func save(to url: URL) throws }`
  - `public struct TranslationProgress: Sendable, Equatable { public let done: Int; public let failed: Int; public let total: Int }`
  - `public struct Pretranslation: Sendable { public init(document: SourceDocument, glossary: Glossary, model: String, memoryURL: URL); public func cached() throws -> [String?]; public func run(using translator: some SentenceTranslator, progress: @Sendable (TranslationProgress) async -> Void) async throws -> [String?] }`

決めてあること:
- `parse`: 空行と `#` 始まりは無視。タブを含む行は TSV、含まない行は最初の `=` で分割し両側を trim。片側が空ならエラー（`name` と行番号を含む日本語メッセージ）。同じ原語（大文字小文字無視）は後の行が上書きし、順序は後の位置へ移る。`overlay` も同じ規則。
- `occurs` は Local Caption と同じ語境界正規表現（`app` は `happens` に一致しない、大文字小文字無視）。
- `kikiyakuText`: `texts` のどれかに出現する用語だけを `terms` の順に `source = target` で1行ずつ、末尾改行付き。該当なしは空文字列。
- PFML3 の組み立てと `LocalTranslator` の要求本文・応答検査は Local Caption の実装と同一（`n_predict` 512、`stop` 3種、`stop_type` が `word`/`eos` 以外や `truncated` はエラー）。移植元テストも移す。
- `key`: 原文の連続空白を1個にして trim したもの、各用語の `source\u{1F}target`、`model` を `\u{1E}` で連結した UTF-8 の SHA-256 小文字 hex。
- `TranslationMemory` の JSON は `{"version":1,"entries":{key:translation}}`。`load` はファイルが無ければ空。`save` は親ディレクトリを作成し atomic に書く。
- `Pretranslation.run`: 文を id 順に処理。保存済みなら再利用（翻訳器を呼ばない）。未訳なら `context` に文書タイトル、`history` に直前の訳済み2文（文書順、段落をまたいでよい）、`glossary` に文に出現する用語だけを持つ `Glossary` を渡す。1文の失敗はその文を `nil` にして続け、3文連続で失敗したら最後のエラーを投げる（それまでの訳は保存済み）。10文ごと・終了時・キャンセル時に `save`。キャンセルは `CancellationError` を投げる。各文の処理後に `progress` を呼ぶ。`cached()` は翻訳器を使わず保存済みの訳だけを id 順で返す。

テストに入れる値（抜粋）:
- `parse("agent\tエージェント\nspeech recognition = 音声認識\n# c\n\nAgent = 代理人", name: "g.txt").terms == [GlossaryTerm("speech recognition","音声認識"), GlossaryTerm("Agent","代理人")]`
- `parse("x =", name: "g.txt")` は `g.txt` と `1` を含むエラー。
- `kikiyakuText(appliedTo: ["The agent runs."])` が `"Agent = 代理人\n"`（`speech recognition` は出現しないので出さない）。
- 事前翻訳: 同一原文2文を含む文書で、偽翻訳器の呼び出しは1回、両文に同じ訳。2回目の `run` は呼び出し0回。3連続失敗で投げ、その前に成功した訳は `cached()` で取れる。

### Task 2: PDF 本文の読み順抽出（`SoeYakuCore`）

**Files:**
- Create: `Sources/SoeYakuCore/ReadingOrder.swift`, `Sources/SoeYakuCore/PDFExtractor.swift`
- Test: `Tests/SoeYakuCoreTests/ReadingOrderTests.swift`, `Tests/SoeYakuCoreTests/PDFExtractorTests.swift`, `Tests/SoeYakuCoreTests/Support/FixturePDF.swift`（CoreText でテスト内に PDF を生成するヘルパー）

**Interfaces:**
- Consumes: `Sentence`, `SourceDocument`
- Produces:
  - `public struct PageLine: Sendable, Equatable { public let text: String; public let bounds: CGRect; public let page: Int }`（`bounds` は PDF ページ空間、左下原点）
  - `enum ReadingOrder { static func order(_ lines: [PageLine], pageBounds: CGRect) -> [PageLine]; static func removeRunningElements(_ pages: [[PageLine]], pageBounds: [CGRect]) -> [[PageLine]]; static func paragraphs(_ flow: [PageLine], pageBounds: [CGRect]) -> [(page: Int, text: String)]; static func sentences(_ paragraph: String) -> [String] }`
  - `public enum PDFExtractor { public static func extract(url: URL) throws -> SourceDocument }`

決めてあること:
- 行は `PDFPage.selection(for:)` の `selectionsByLine()` から取る（PDFKit は段ごとの行を返すことを確認済み）。ページ順はそのまま、ページ内の順は `order` が座標で決める。
- `order`: 中央 `midX`、許容 `0.05 × 幅`。`maxX <= midX + 許容` かつ `minX < midX` を左段、`minX >= midX - 許容` を右段、それ以外を全幅とする。左段と右段がそれぞれ3行以上あれば二段組みとし、全幅の行で上下の帯に区切り、帯ごとに左段（上→下）→右段（上→下）。二段組みでなければ上→下、同じ高さは左→右。
- `removeRunningElements`: ページ上端・下端の各8%の帯にある行のうち、数字だけ（ローマ数字の小文字 i–xii を含む）の行と、数字を除いて小文字化した文字列が3ページ以上かつ全ページの30%以上に出る行を除く。
- `paragraphs`: 次のどれかで段落を切る。同じページ・同じ段（x 範囲が重なる）で前行との縦の空きが前行の高さの0.8倍超／行の高さが前行と25%超違う／前行が終止記号（`.?!:` と閉じ引用符・閉じ括弧の後に続くものを含む）で終わり、かつ今の行が段の左端より前行の高さの0.5倍超字下げされている。段・ページの移り目では、前行が終止記号で終わり、かつ前行の幅がその段の最長行の0.8倍未満のときだけ切る。行の連結は、前行が「英字＋`-`」で終わり今の行が小文字で始まるならハイフンを除いて空白なしで、それ以外は空白1個で行う。
- `sentences`: `NLTokenizer(unit: .sentence)` で分割し、trim して空を除く。
- `extract`: 文字列は NFKC 正規化（合字 `ﬁ` → `fi`）。`title` は PDF の Title 属性、無ければファイル名（拡張子なし）。`fingerprint` はファイルの SHA-256。テキスト層が無い（文が0件）ならエラー「この PDF には文字情報がありません。」。

テストに入れる値（抜粋）:
- 生成 PDF（1ページ目：上端に走りヘッダー "Running Header" とページ番号、全幅の題、二段組みの本文、左段の最後の文が右段の先頭へ続く。2ページ目：同じヘッダー、見出し "Results"、本文、ページをまたぐ文）から、見出し "Results" が独立した段落になり、ヘッダーとページ番号が文に含まれず、段またぎ・ページまたぎの文がそれぞれ1文として得られる。
- 抽出は文書順を保つ: 左段の各文の id は右段の各文の id より小さい（PDF の描画を右段→左段の順にしても）。

### Task 3: 現在地照合と座標変換（`SoeYakuCore`）

**Files:**
- Create: `Sources/SoeYakuCore/TextNormalizer.swift`, `Sources/SoeYakuCore/Locator.swift`, `Sources/SoeYakuCore/ScreenGeometry.swift`
- Test: `Tests/SoeYakuCoreTests/LocatorTests.swift`, `Tests/SoeYakuCoreTests/ScreenGeometryTests.swift`

**Interfaces:**
- Consumes: `Sentence`, `SourceDocument`
- Produces:
  - `public enum TextNormalizer { public static func tokens(_ text: String) -> [String] }`
  - `public struct TextLine: Sendable, Equatable { public let text: String; public let box: CGRect }`（`box` は取得画像に対する正規化座標 0〜1、左上原点）
  - `public enum LocateResult: Sendable, Equatable { case matched(sentence: Int, confidence: Double); case unresolved }`
  - `public struct DocumentIndex: Sendable { public init(_ document: SourceDocument) }`
  - `public struct Locator: Sendable { public init(index: DocumentIndex); public private(set) var lastSentence: Int?; public mutating func locate(lines: [TextLine], pointer: CGPoint) -> LocateResult }`
  - `public enum ScreenGeometry { public static func topLeft(fromVision box: CGRect) -> CGRect; public static func normalizedPointer(mouse: CGPoint, primaryScreenHeight: CGFloat, windowFrame: CGRect) -> CGPoint? }`

決めてあること:
- `tokens`: NFKC → 小文字化 → アポストロフィ（`'` `’`）は削除 → 英数字以外は空白 → 空白で分割。
- `DocumentIndex`: 全文の token 列と各 token の文 id、token 3-gram → 出現位置の表。出現が64回を超える 3-gram は照合に使わない。
- `locate` の手順:
  1. 基準行: `pointer` が行の箱（上下に行の高さの0.5倍の余白）に縦で入り、横は箱 ±0.02 に入る行。無ければ、横が重なる行のうち縦の距離が行の高さの2倍以内で最も近い行。無ければ `unresolved`。
  2. 文脈: 基準行と横の重なりが狭い方の幅の50%以上ある行を縦に並べ、基準行の上下それぞれ最大2行を加えた問い合わせ列を作る。行末が「英字＋`-`」の行は次の行の最初の token と結合する。
  3. 問い合わせの各 3-gram（位置 q）について、出現位置 p ごとにずれ d = p − q に1票。±3 の範囲の票を合算したものを d の得点とし、最高得点の d* を選ぶ。最高得点が2未満、または問い合わせの 3-gram 数の25%未満なら `unresolved`。
  4. d* から30 token 超離れた別のずれが最高得点の0.75倍以上なら曖昧。`lastSentence` があればその文の位置に近い方を採り、無ければ `unresolved`。
  5. ポインターの横位置を基準行の箱の中の割合にして基準行の token を選び、その位置 d* + q の文 id を返す。`confidence` は最高得点 ÷ 問い合わせの 3-gram 数。`matched` のときだけ `lastSentence` を更新する。
- `topLeft`: `CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)`。
- `normalizedPointer`: `mouse` は Cocoa のグローバル座標（主画面の左下原点）、`windowFrame` は CG のグローバル座標（主画面の左上原点）。`y = primaryScreenHeight - mouse.y` に直して窓内の割合を返す。窓外は `nil`。

テストに入れる値（抜粋）:
- 同じ見出し "Results" が2回ある文書で、見出し行だけでは `unresolved`、下の本文行を文脈に含めると2回目の見出しの文を返す。直前位置が1回目の近くで文脈が見出しだけのときは1回目を返す。
- OCR に文書にない行（"File Edit View"、"Page 3 of 12"）しか無いときは `unresolved` で `lastSentence` は変わらない。
- 上端で切れた行（先頭数語が欠ける）にポインターを置いても、その文を返す。
- 二段組みで左右の段が同じ高さにある OCR 行のとき、ポインターの x がある側の段の文を返す。
- `normalizedPointer(mouse: (150, 700), primaryScreenHeight: 1000, windowFrame: (100, 200, 400, 200)) == (0.125, 0.5)`。窓外は `nil`。

### Task 4: Vision 文字認識と CLI（`SoeYakuVision`・`SoeYakuCLI`）

**Files:**
- Modify: `Package.swift`（`SoeYakuVision` ライブラリ、`soeyaku-cli` 実行ファイル、`SoeYakuVisionTests` を追加）
- Create: `Sources/SoeYakuVision/TextRecognizer.swift`, `Sources/SoeYakuCLI/main.swift`
- Test: `Tests/SoeYakuVisionTests/EndToEndTests.swift`

**Interfaces:**
- Produces: `public enum TextRecognizer { public static func lines(in image: CGImage) async throws -> [TextLine]; public static func warmUp() async }`（Swift の Vision API `RecognizeTextRequest`、英語 `en-US`・`.accurate`・言語補正あり。箱は `ScreenGeometry.topLeft` で左上原点に直す。`warmUp` は文字を1行描いた小さな画像を1回認識して結果とエラーを捨てる。初回の認識はモデル読み込みで数十秒かかり、2回目以降は1画面0.1秒程度であることを確認済み）
- CLI: `soeyaku-cli extract FILE.pdf`（文を JSON Lines）／`soeyaku-cli translate FILE.pdf --port N [--api-key K] [--glossary FILE]... [--memory FILE] [--model NAME]`（事前翻訳して `{"id","en","ja"}` を JSON Lines）／`soeyaku-cli locate FILE.pdf IMAGE.png --pointer X,Y`（画像ピクセル座標。`{"status","sentence","text","confidence"}` を1行）

決めてあること:
- 結合テスト: Task 2 の生成 PDF の一部を2倍で描画した画像を「画面」とし、Vision → `Locator` で、指定した文の行にポインターを置いたとき、その文の id が返る。文の行位置は `PDFDocument.findString` の選択範囲から求める。

### Task 5: アプリ（`SoeYakuApp`）

**Files:**
- Modify: `Package.swift`、Create: `Sources/SoeYakuApp/*.swift`, `App/Info.plist`, `Scripts/build-app.sh`（Local Caption の署名手順を流用）, `README.md`

決めてあること:
- 操作窓: PDF を開く（`SoeYakuCore.PDFExtractor`）、「プレビューで開く」、翻訳モデル（GGUF）の選択、全文翻訳の開始・中断と進捗、共通の用語集と文書の用語集を開く（無ければ説明コメント入りで作成）、Kikiyaku 用に適用用語をコピー、追従の開始・停止。
- 保存先: `~/Library/Application Support/SoeYaku/glossary.txt`（共通）、`.../Documents/<fingerprint>/glossary.txt`（文書別）、`.../Documents/<fingerprint>/memory.json`。
- 訳文窓: 非アクティブ化 `NSPanel` の `NSTextView`。段落ごとに訳文を連結（未訳の文は原文を淡色で表示）、現在の文を背景色で強調し中央へスクロール。下端に現在地の原文、または「現在地を特定できません」。
- 追従: 0.4秒ごとに、プレビューが最前面かつポインターがその最前面ウインドウ内のときだけ、`SCScreenshotManager` でそのウインドウだけを backing scale の画素数で取得し、画像が前回と同じなら OCR を省いて `Locator.locate` する。画面収録の許可が無ければ状況を表示して止まる（迂回しない）。
