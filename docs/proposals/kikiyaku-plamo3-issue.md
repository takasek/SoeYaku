# PLaMo 3 Translate に翻訳方向と用語集を構造化して渡す対応の相談

ローカルの PLaMo 3 Translate 2B を Kikiyaku から使う場合、翻訳方向と用語集をモデル専用の構造化指定へ渡す対応について相談したいです。既定の OpenAI 互換要求では、これらを含むシステム指示がモデルのテンプレートで除外されることを、入力と出力の両方で確認しました。

## 確認条件

- Kikiyaku: `8dcc192421937bf0fd632809f53899319b65eb37`。アプリのソースは未変更です。
- Apple Silicon M5、macOS 27.2、llama.cpp build 11960 (`8642541b2`)。
- PLaMo 3 Translate 2B Q4_K_M GGUF と[配布元の固定版テンプレート](https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/blob/f2b4599dff9b3e45c62567eac15e83186b4cb64e/chat_template.jinja)。再取得したテンプレートは試験時のファイルとバイト一致しています。
- Kikiyaku の既定プロンプト、`source` / `target` 付き発話タグ、[既存の用語集形式](https://github.com/utahta/kikiyaku/blob/8dcc192421937bf0fd632809f53899319b65eb37/Sources/kikiyaku/TranslationPrompt.swift)を使用。

## 用語集を変えてもモデル入力が同じになる

`standard output` を含む同じ英文について、用語集なし／「標準出力」／識別用の「標準出力ストリーム」／識別用の「stdout」の4条件を送り、llama.cpp の `/apply-template` で実際の入力を確認しました。4条件の結果は全文一致し、PFMLのglossaryブロックがありませんでした。

別途、保存済み認識原文・公式字幕原文・資料の文を固定した72条件を、実際の `OpenAICompatSession` の新規セッションで比較しました。通常の用語集なし／ありの11組も、既存接続の出力は11/11で同一でした。

同じモデルへ用語と言語をPFMLで渡すローカル補助を挟んだ場合、例えば次の同一入力で差が出ます。

> In most cases, you’ll launch a subprocess using a FilePath to specify the full path to an executable.

| 指定 | 構造化して渡したときの訳語 |
| --- | --- |
| 用語集なし | サブプロセス、実行ファイル |
| `subprocess = 子プロセス`、`executable = 実行プログラム` | 子プロセス、実行プログラム |

## 翻訳方向も同じ入力で比較

| 同じ原文と指定方向 | 既存接続 | 構造化した経路 |
| --- | --- | --- |
| 水曜日の会議は中止です。／日→英 | 水曜日の会議は中止です。 | Wednesday's meeting is cancelled. |
| 子プロセスを起動します。／日→英 | 子プロセスを起動します。 | Launch a subprocess. |

## 接続の欠落とモデルの指定無視を分けた確認

「標準出力」は指定なしでも出るため、用語集の効果の証拠には数えませんでした。同じ3入力に「標準出力ストリーム」「stdout」を指定した6条件では、既存接続は0/6、正しく構造化した経路は3/6で指定訳を採用しました。

この6条件では、公式テンプレートへタグなし原文と `chat_template_kwargs` の `source_lang` / `target_lang` / `glossary` を渡したPFMLと、補助の実送信PFMLが6/6で全文一致しました。補助経由、同一要求のモデル直送、正しい構造化指定のchat接続の出力も6/6で一致し、未採用の3条件も同じまま再現しました。したがって、モデルが指定を採用しない現象は別にありますが、システム指示のままでは指定自体が入力から消えることは切り分けられています。

## 実字幕と資料での利用

[WWDC2025「What’s New in Swift」](https://developer.apple.com/videos/play/wwdc2025/245/)の36秒を通常のKikiyakuで認識・翻訳・字幕表示し、関連するSwift Subprocess READMEの8文を文書読書用のローカルツール SoeYaku で訳しました。両方で「子プロセス」「標準出力」が現れました。

実字幕の5発話を同じ発話順で履歴を引き継ぎつつ固定テキストとして再生すると、補助＋元の用語集の5訳は保存された実字幕と5/5で全文一致しました。同じ条件の辞書なし再生では一般名詞が「サブプロセス」「実行ファイル」になり、既存接続は辞書の有無で5/5同じ訳でした。各群はその群の訳を履歴に使うので、発話列全体への設定の効果として比較しています。個別入力への直接効果は、履歴なしの対照比較で確認しています。

## 相談したい対応

PLaMo 3 Translate 向けに、発話のsource / target、該当する用語、同じ方向の直近対訳を構造化して渡す対応は、プロジェクトの方針に合いそうでしょうか。

今回、PFMLを `/completion` へ渡す方法に加え、[llama.cpp の `chat_template_kwargs`](https://github.com/ggml-org/llama.cpp/blob/b11960/tools/server/README.md) を正しく使うchat接続でも同じ入力と出力になることを確認しました。既存HTTP接続を活かす方法か、`LLMTranslator` に専用の翻訳器を加える方法かを含め、対応方針をご相談できればと思います。
