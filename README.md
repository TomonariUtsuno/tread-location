# tread wheel map prototype

## ローカルで開く

このフォルダで次を実行し、表示されたURLをスマートフォンまたはPCのブラウザで開きます。

```sh
python3 -m http.server 8000
```

地図タイルの表示にはインターネット接続が必要です。

## GitHub Pagesで公開する

このフォルダの中身をGitHubリポジトリへ置き、リポジトリの Settings > Pages で公開元を選択します。サーバー側の処理やAPIキーは不要です。

公開前に `data.js` と `wheels` フォルダを本番データへ差し替えます。画面上には画像ファイル名を表示しない設計です。
