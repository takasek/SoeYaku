# 検証記録

- [PDF文書とPreviewへの追従](pdf-document-mode-2026-11-06.md)
- [HTML文書とブラウザへの追従](html-document-mode-2026-11-06.md)
- [枠1・枠2](frame-modes-2026-11-06.md)
- [Kikiyakuの実字幕と資料訳](kikiyaku-glossary-demo-2026-11-06.md)
- [用語集と翻訳方向の対照検証](glossary-controls-2026-11-07.md)

各記録は、開発時の条件・確認できた範囲・残る制約を記載しています。記録内の `local/evaluations/` は開発機での保存場所です。取得した文書、動画、画面画像、モデル、生成した訳文、詳細ログは公開リポジトリに同梱していません。

自動試験のコードと生成用の文書fixtureは `Tests/` にあります。Macでリポジトリのルートから実行します。

AppKitのフォーカス・スクロール試験には、ロックを解除して画面を利用できるGUIセッションが必要です。画面が利用できない環境ではkey windowやアニメーションを確認できないため、ヘッドレス環境だけで全件の成功を判定しないでください。

```sh
swift test
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/AdapterTests -v
```

自動試験の成功と、アプリの画面を操作した確認は別の結果です。少数資料での実機確認を、一般の文書・ゲームや長時間利用の品質保証とは扱いません。

## 初回公開前の再確認（2026-11-07）

Swiftの全180件（Core132、Vision9、Runtime5、CLI19、App15）と、接続補助の17件が成功しました。最初の実行ではkey windowがnilとなり、フォーカス・スクロール試験の3件が失敗しました。画面の応答を確認した後、同じコードの単独試験5件と全180件が成功しています。試験を省略したり、期待値を緩めたりはしていません。
