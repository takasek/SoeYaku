# PLaMo 3 Translate の翻訳方向・用語集を渡す翻訳器の追加相談

ローカルの PLaMo 3 Translate 2B を Kikiyaku の翻訳器として使った際、既存の OpenAI 互換接続では用語集と翻訳方向をモデルへ反映できない構成があったため、専用の翻訳器を追加する方針をご相談したいです。

Kikiyaku 本体の不具合全般という主張ではなく、PLaMo の専用入力形式と OpenAI 互換接続の間の扱いについての相談です。

## 確認した条件

- Kikiyaku: `8dcc192421937bf0fd632809f53899319b65eb37`（11月7日の確認時点の main）。アプリのソースは変更していません。
- Apple Silicon M5、macOS 27.2。
- llama.cpp build 11960 (`8642541b2`)、PLaMo 3 Translate 2B Q4_K_M GGUF。
- 比較元は、[モデル公式の chat template](https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/blob/f2b4599dff9b3e45c62567eac15e83186b4cb64e/chat_template.jinja) と、Kikiyaku 既定のシステムプロンプト・発話タグです。
- 用語集: `subprocess = 子プロセス`、`standard output = 標準出力`、`executable = 実行プログラム`。

## 再現した違い

英→日の入力は次の1文です。

> In most cases, you’ll launch a subprocess using a FilePath to specify the full path to an executable.

Kikiyaku と同じ要求形式で `/v1/chat/completions` に送ると、用語集なし／ありとも「実行ファイル」「サブプロセス」になりました。公式テンプレートでは先頭のシステム指示を除外するため、[Kikiyaku がそこに加える用語集](https://github.com/utahta/kikiyaku/blob/8dcc192421937bf0fd632809f53899319b65eb37/Sources/kikiyaku/TranslationPrompt.swift)がこの経路ではモデルに届かないと考えています。

同じモデルへ `/completion` で PLaMo の PFML3 形式を直接渡し、`glossary`、`input lang=en`、`output lang=ja` を指定すると、用語集なしは「実行ファイル」「サブプロセス」、ありは「実行プログラム」「子プロセス」になりました。

日→英の方向も別途確認しました。公式テンプレートと既存形式の要求では「水曜日の会議は中止です。」が日本語のまま返りました。PFML3 に変換するローカル補助を挟み、実際の `OpenAICompatSession` で「子プロセスを起動します。」を送った試験では “Launch a subprocess.” になっています。ここは異なる入力での方向確認であり、同一文の比較ではありません。

## 実字幕での確認

上の補助を Kikiyaku の OpenAI 互換接続先に指定し、[WWDC2025「What’s New in Swift」](https://developer.apple.com/videos/play/wwdc2025/245/)の36秒の音声をシステム音声から認識させました。5発話が翻訳され、「subprocess → 子プロセス」は該当4発話、「standard output → 標準出力」は1発話、「executable → 実行プログラム」は2発話で指定訳が現れました。1発話に複数語が現れるので、合計は発話数と一致しません。

別の文書を読むローカルツール SoeYaku でも、関連する Swift Subprocess README の抜粋8文を同じ用語で訳し、「子プロセス」「標準出力」が両方に現れることを確認しました。字幕は通常の Kikiyaku の UI を使い、音声認識や字幕窓を独自実装したものではありません。

短い1素材の確認で、認識誤りや固有名詞の訳し過ぎは残っています。また「標準出力」は指定なしでも出る語なので、その語だけで用語集の効果を立証するものではありません。

## 相談したい範囲

既存の `LLMTranslator` の拡張口に、PLaMo 3 Translate 向けに次を扱う翻訳器を加える方向は、プロジェクトの方針に合いそうでしょうか。

- source / target を PFML3 の言語指定へ渡す。
- 発話に該当する用語を PFML3 の glossary へ渡し、逆方向では対訳を交換する。
- 同じ翻訳方向の直近の対訳を文脈として渡す。2B の今回の確認では、反対方向の例を混在させると出力方向が崩れ、同方向の直近3対訳に絞ると回復しました。

まずは翻訳器への対応に相談を絞りたいです。別ツールとの自動辞書同期や用語集ファイルの取り込みは、この提案には含めません。
