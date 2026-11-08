# ローカル翻訳モデルの準備

SoeYaku は Mac 上で動く PLaMo 3 Translate に英語の文を1文ずつ渡し、日本語訳を文書ごとに保存します。モデルの取得後は、翻訳にインターネット接続を使いません。

## 2B モデルを用意する

Apple Silicon、Xcode のコマンドラインツール、Homebrew を使います。開発時の llama-server は build 11960 です。次のコマンドはリポジトリのルートで実行します。

```sh
brew install llama.cpp
mkdir -p local/models
model=local/models/plamo-3-translate-2b-Q4_K_M.gguf
curl --fail --location --continue-at - --output "$model.partial" \
  https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/resolve/f2b4599dff9b3e45c62567eac15e83186b4cb64e/plamo-3-translate-2b-Q4_K_M.gguf
printf '%s  %s\n' 2c288ecc7ebfe60c3561726580da3583767f3c41ca3ef5c6825bf6c4cc060787 "$model.partial" \
  | shasum -a 256 -c - && mv "$model.partial" "$model"
```

ダウンロードは約 1.81 GB です。同じモデルを取得済みなら、`local/models/` にコピーするかシンボリックリンクを張れば足ります。モデルの使用条件と配布条件は [配布元のモデルカード](https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF) を参照してください。`local/models/` 以外に置いた場合は、アプリの「モデル…」で GGUF を選びます。

## サーバーを手動で起動する

アプリは翻訳のたびにサーバーを自動で起動・終了します。`soeyaku-cli translate` を使う場合だけ、次のように手動で起動します。

```sh
Scripts/start-model.swift local/models/plamo-3-translate-2b-Q4_K_M.gguf 8080
```

別のターミナルで `curl --noproxy '*' -f http://127.0.0.1:8080/health` が成功したら使えます。停止は起動したターミナルで Control-C を押してください。起動時に GGUF のヘッダーから位置補正（YaRN）を計算します。build 11960 と上の 2B モデルでは `--yarn-beta-fast 31.738495 --yarn-beta-slow 1.0040927` になります。

## 翻訳リクエスト

llama-server の `/completion` に PFML3 形式のプロンプトを渡します。翻訳方向は英語から日本語に固定し、文書のタイトルを context に、直前に訳した2文を対訳履歴に、その文に出現する用語だけを glossary に入れます。生成は 512 トークンを上限とし、上限到達または入力切り捨てを検出した場合はその文を未訳として残します。チャット形式の `/v1/chat/completions` は使いません。PLaMo 公式のチャットテンプレートは先頭のシステム指示を除外するため、用語集や翻訳方向をシステム指示で渡しても反映されないからです。[PFML3 書式と用語集の例](https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF/blob/f2b4599dff9b3e45c62567eac15e83186b4cb64e/README_ja.md)
