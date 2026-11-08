# PLaMo 3 Translate接続時に翻訳方向と用語集が生成用入力へ渡らない

> 投稿準備時の草稿です。ユーザーが投稿した最終本文は [Kikiyaku Issue #17](https://github.com/utahta/kikiyaku/issues/17) を参照してください。

KikiyakuのOpenAI互換接続でPLaMo 3 Translate 2Bを使うと、翻訳方向と用語集の指定形式が食い違い、設定が生成用入力から落ちます。構成はllama.cppのllama-serverと、PLaMo配布元のテンプレートです。

PLaMoのように専用の指定形式を持つ翻訳モデルは、意図的に対応範囲から外しているのでしょうか。意図した制限でなければ、**原文・翻訳方向・用語集をPLaMo用の形式へ変換する処理を追加し、設定が生成用入力に含まれるよう修正をお願いします。** 意図した制限であれば、必要なモデルの条件をREADMEへ明記していただきたいです。

## 指定形式の食い違い

HTTPのChat Completions要求としては受理されますが、翻訳設定の読み方が異なります。

| 情報 | Kikiyakuが送る内容 | PLaMoのテンプレートが読む指定 | 現在の結果 |
| --- | --- | --- | --- |
| 翻訳方向 | 本文の `<u source="…" target="…">` 属性 | `source_lang` / `target_lang` | タグは本文として扱われ、翻訳先は既定の日本語になる |
| 用語集 | systemメッセージ内の `<glossary>` | `glossary` 配列 | 先頭のsystemメッセージが除外され、用語指定が入力に入らない |

KikiyakuのREADMEにはllama.cppなどのOpenAI互換APIへ接続できるとありますが、専用形式の翻訳モデルを対象外とする記載はありません。Kikiyakuがsystem指示と発話タグを使う設計は実装に現れており、PLaMo側にもsystemメッセージを除外する処理があります。この組み合わせを対応範囲に含める意図があるかは、公開資料だけでは分かりません。

## 同じ原文での再現結果

単方向翻訳で、同じモデル・同じ原文に対して次の差があります。

| 設定と入力 | Kikiyakuから直接接続 | 送信形式を変換するアダプタ経由 |
| --- | --- | --- |
| `subprocess = 子プロセス`、`executable = 実行プログラム` | サブプロセス、実行ファイル | 子プロセス、実行プログラム |
| 日→英で「水曜日の会議は中止です。」 | 水曜日の会議は中止です。 | Wednesday's meeting is cancelled. |

最初の行の原文は次の1文です。

> In most cases, you’ll launch a subprocess using a FilePath to specify the full path to an executable.

ここでいうアダプタは、Kikiyakuから届いた要求から原文・翻訳方向・用語集を取り出し、PLaMo用の入力形式に変換してllama-serverへ送るプログラムです。Kikiyaku本体は変更していません。アダプタ経由でも辞書を外すと「サブプロセス」「実行ファイル」に戻ります。

PLaMoを対応範囲に含める場合、必要なのは、タグを外した原文、PLaMoの言語コードへ対応付けた翻訳方向（例：`en-US → en`、`ja-JP → ja`）、翻訳方向に沿った用語の配列を渡すことです。`/completion` への切替に固定する必要はなく、llama-serverの既存chat APIへ `chat_template_kwargs` を渡す形も使えます。モデル名と生成設定を省いた要求例は次のとおりです。

```json
{
  "messages": [{
    "role": "user",
    "content": "This returns an ExecutionResult containing the process identifier, termination status, and collected standard output and standard error."
  }],
  "chat_template_kwargs": {
    "source_lang": "en",
    "target_lang": "ja",
    "glossary": [{
      "source": "standard output",
      "target": "標準出力ストリーム"
    }]
  }
}
```

修正をお願いしたいのは、指定された情報が生成用入力に含まれることです。入力に含まれた用語をモデルが必ず採用するという保証は求めていません。別途、識別用の訳語6条件中3条件は、正しい入力をモデルへ直接送っても不採用でした。

<details>
<summary>再現条件と根拠</summary>

- Kikiyaku: `8dcc192421937bf0fd632809f53899319b65eb37`。既定プロンプトと[既存の用語集形式](https://github.com/utahta/kikiyaku/blob/8dcc192421937bf0fd632809f53899319b65eb37/Sources/kikiyaku/TranslationPrompt.swift)を使用。
- Apple Silicon M5、macOS 27.2、llama.cpp build 11960 (`8642541b2`)。
- PLaMo 3 Translate 2B Q4_K_M GGUFと[配布元の固定版テンプレート](https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/blob/f2b4599dff9b3e45c62567eac15e83186b4cb64e/chat_template.jinja)。
- [Kikiyakuの接続設定](https://github.com/utahta/kikiyaku/blob/8dcc192421937bf0fd632809f53899319b65eb37/README.md#local-server)、[発話タグの規約](https://github.com/utahta/kikiyaku/blob/8dcc192421937bf0fd632809f53899319b65eb37/Sources/kikiyaku/ClaudeTranslator.swift)、[llama.cppの追加パラメータ](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/README.md)。

代表入力について用語集を4通りに変えても、直接接続の `/apply-template` が返す生成用入力は全文同一で、用語指定のブロックがありません。辞書なし／ありの11組でも訳文は変わりません。

識別用に `standard output = 標準出力ストリーム` と `standard output = stdout` を3入力ずつへ指定した結果は、直接接続で0/6、アダプタ経由で3/6の採用です。通常の「標準出力」は指定なしでも出るため、用語集の効果には数えていません。

この6条件では、構造化したchat要求から公式テンプレートが生成する入力と、アダプタが送るPLaMo専用書式（PFML）が全文一致しています。アダプタ経由・同一要求のモデル直送・構造化したchat接続の訳文も、成功と不採用を含めて条件ごとに同じです。これにより、設定が入力から落ちる問題と、モデルの用語不採用を分けています。

実利用では、Kikiyaku本体と上記アダプタで[WWDC2025の講演](https://developer.apple.com/videos/play/wwdc2025/245/)36秒の5発話を字幕表示し、関連資料8文の訳と「子プロセス」「標準出力」が共通して現れています。この記録は利用例で、用語集の効果の根拠は上の同一入力の比較です。

</details>
