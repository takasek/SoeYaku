# PLaMo 3 Translate向けの送信方式を追加する提案

Kikiyakuに、PLaMo 3 Translate向けに翻訳方向と用語集を渡す送信方式を追加する提案は、プロジェクトの方針に合うでしょうか。

現在はKikiyaku本体を変更せず、外部の変換補助を別に起動して連携できています。この変換を本体で行えれば、利用者が変換補助を起動・終了する手間を省けるため、PLaMo向けの送信方式を対応範囲に含める意向を伺いたいです。

検証にはllama.cppのllama-server、PLaMo 3 Translate 2BのGGUF、配布元のテンプレートを使いました。この組み合わせでは現在の要求のままだと設定がモデルへ届かず、渡し方を変えると反映されることを確認しました。

## 現在の要求と、動作を確認した要求の違い

Kikiyakuは翻訳方向を `<u source="…" target="…">` タグに、用語集をsystemメッセージに載せています。PLaMoの配布元テンプレートは先頭のsystemメッセージを除外し、発話タグも翻訳する本文として扱うため、これらがモデル用の言語指定・用語指定にはなっていませんでした。

こちらで動作を確認したのは、llama-serverの `/v1/chat/completions` へ、タグを外した原文と、言語・用語をllama.cppの追加パラメータ `chat_template_kwargs` で渡す形です。次は実際に比較したリクエストから、モデル名と生成設定を省いた例です。

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

この指定は、llama-serverがPLaMo専用の入力書式（PFML）へ変換します。検証では、Kikiyakuの要求をPFMLへ変換して `/completion` に送る補助も作り、同じモデルで両方の入力・出力が一致することを確かめました。

## 同じ入力で起きた違い

以下の「標準接続」は既存のOpenAI互換接続、「変換補助あり」はKikiyakuと同じサーバーの間に上記の補助を挟んだ接続です。Kikiyaku本体のソースは変更していません。

| 設定した内容 | 標準接続 | 変換補助あり |
| --- | --- | --- |
| `subprocess = 子プロセス`、`executable = 実行プログラム` | サブプロセス、実行ファイル | 子プロセス、実行プログラム |
| 日→英で「水曜日の会議は中止です。」を翻訳 | 水曜日の会議は中止です。 | Wednesday's meeting is cancelled. |

最初の行は、次の同じ原文で比較しました。変換補助ありでも用語集を外すと「サブプロセス」「実行ファイル」に戻るため、接続を変えただけの差とも区別しています。

> In most cases, you’ll launch a subprocess using a FilePath to specify the full path to an executable.

指定を届けた後も、モデルが採用しない例はありました。「標準出力」は指定なしでも出るため効果の証拠にせず、「標準出力ストリーム」「stdout」という識別用指定を同じ3入力で試すと、標準接続は0/6、変換補助ありは3/6の採用でした。採用されなかった3条件は、同じ要求をモデルへ直送しても再現しています。今回の相談では、この生成結果と、設定自体が入力から消える問題を分けています。

<details>
<summary>再現環境と、追加で確認したこと</summary>

- Kikiyaku: `8dcc192421937bf0fd632809f53899319b65eb37`。既定プロンプトと[既存の用語集形式](https://github.com/utahta/kikiyaku/blob/8dcc192421937bf0fd632809f53899319b65eb37/Sources/kikiyaku/TranslationPrompt.swift)を使用。
- Apple Silicon M5、macOS 27.2、llama.cpp build 11960 (`8642541b2`)。
- PLaMo 3 Translate 2B Q4_K_M GGUFと[配布元の固定版テンプレート](https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/blob/f2b4599dff9b3e45c62567eac15e83186b4cb64e/chat_template.jinja)。テンプレートは再取得して試験時のファイルとのバイト一致を確認。
- `chat_template_kwargs` の仕様は [llama.cppのサーバー文書](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/README.md)を参照。

標準接続では、代表入力の用語集を4通りに変えても、`/apply-template` が返すモデル入力は同じで、用語指定のブロックがありませんでした。固定した原文の辞書なし／ありの11組でも、訳文が変わりませんでした。これは指定が反映されないことを確かめる比較です。

識別用指定の6条件では、上記の構造化指定から得たPFMLと、補助が実送信したPFMLがすべて一致しました。補助経由・モデル直送・構造化したchat接続の訳文も条件ごとに一致し、失敗3条件も同じままでした。これは失敗が補助による変換や出力加工で生じたものかを切り分ける比較です。

実利用の確認では、**Kikiyaku本体＋変換補助**で[WWDC2025の講演](https://developer.apple.com/videos/play/wwdc2025/245/)36秒の5発話を字幕表示しました。別途、関連資料8文をSoeYakuで訳し、「子プロセス」「標準出力」が両方に現れることを確認しています。この記録は字幕と資料訳を併用できることの確認で、用語集の効果は上の固定入力の比較で調べました。

</details>
