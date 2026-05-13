# aws-hyperpod-slurm-hello-world

Amazon SageMaker HyperPod の最小構成（1 ノード）で Slurm hello world と GPU 認識テストを実施するためのサンプル一式です。

## コスト警告（最重要）

HyperPod は **クラスタ起動中ずっと課金** されます（Training Job のような「ジョブ単位課金」ではありません）。

| 項目 | 値 |
|:--|:--|
| インスタンス | `ml.g5.2xlarge` × 1 ノード（A10G 24GB） |
| 課金モード | On-Demand |
| 1 日放置のコスト | 約 **$53/日 ≒ 約 8,000 円/日** |
| 推奨運用 | 作成 → 即動作確認 → 即 `scripts/teardown.sh` |

**動作確認後は必ず `scripts/teardown.sh` を実行してください。**

## 構成

| リソース | 命名 |
|:--|:--|
| VPC | `aws-hyperpod-slurm-hello-world-vpc`（プライベートサブネット 1 + NAT Gateway 1） |
| IAM Role | `aws-hyperpod-slurm-hello-world-execution-role` |
| S3 Bucket | `aws-hyperpod-slurm-hello-world-<account-id>-lifecycle` |
| HyperPod クラスタ | `aws-hyperpod-slurm-hello-world`（1 InstanceGroup / 1 ノード / `ml.g5.2xlarge`） |

## ディレクトリ構成

```
.
├── cdk/                          # AWS CDK (TypeScript)
├── lifecycle/                    # HyperPod ノード起動時のセットアップ
│   ├── README.md
│   ├── provisioning_parameters.json  # 自前(controller_group 指定)
│   └── config.py.override            # 自前(AWS Samples の config.py 上書き)
│   # 上記以外は scripts/sync-lifecycle.sh で AWS Samples から取り込み
├── scripts/                      # 運用スクリプト
│   ├── sync-lifecycle.sh         # AWS Samples の lifecycle スクリプト取り込み
│   ├── create.sh                 # クラスタ作成(課金開始)
│   ├── connect.sh                # SSM Session Manager で接続
│   └── teardown.sh               # クラスタ削除完了待ち + CDK destroy
├── jobs/                         # 動作確認用 Slurm ジョブ
│   ├── hello.py                  # torch.cuda.is_available() 確認
│   └── hello.sh                  # sbatch スクリプト
├── cluster-config.json           # InstanceGroup 定義(プレースホルダ入り)
├── README.md
└── README.ja.md
```

## 前提

- AWS アカウントに `ml.g5.2xlarge for cluster usage` のクォータが 1 以上ある（リージョン `ap-northeast-1`）
- ローカルに `aws` CLI / `pnpm` / Node.js 20+ / `git` / `jq` / Python 3 / Session Manager プラグインがインストール済み
- AWS 認証情報設定済み（`aws configure` または環境変数）

## 構築手順

```bash
# 1. リポジトリ取得
git clone https://github.com/furuya02/aws-hyperpod-slurm-hello-world.git
cd aws-hyperpod-slurm-hello-world

# 2. lifecycle スクリプト取り込み(AWS Samples の base-config を lifecycle/ に展開)
./scripts/sync-lifecycle.sh

# 3. CDK 依存インストール
cd cdk
pnpm install

# 4. CDK ブートストラップ(初回のみ)
pnpm cdk bootstrap

# 5. CDK デプロイ(VPC / IAM / S3 を作成。NAT Gateway の課金がこの時点から発生)
pnpm cdk deploy
# アカウント ID 部分を任意の suffix に置換する場合:
# pnpm cdk deploy -c bucket_suffix=20260514

# 6. クラスタ作成(ここから ml.g5.2xlarge の課金開始)
cd ..
./scripts/create.sh
```

## 動作確認

```bash
# SSM Session Manager でノードに接続
./scripts/connect.sh

# (以降はノード内)
sinfo                  # Slurm クラスタ状態
srun -N1 hostname      # シンプル実行
srun -N1 nvidia-smi    # GPU 認識確認

# ダミー Python ジョブ
sbatch /path/to/hello.sh
squeue
cat hello.*.out
```

## 削除（必須）

```bash
./scripts/teardown.sh
```

- クラスタ削除完了待ち → CDK スタック削除（NAT Gateway 含む） の順で実行されます
- 完了後、AWS Cost Explorer で当日 / 翌日の SageMaker / EC2 料金が 0 円になっていることを必ず確認してください

## 注意事項

- 本サンプルはエラーハンドリングを最小化しています。本番利用は想定していません
- `lifecycle/` 配下に `scripts/sync-lifecycle.sh` で取り込んだファイルは git 管理外（`.gitignore`）です
- 1 ノードで Slurm controller + worker を兼用する設計です（`provisioning_parameters.json` の `controller_group` をインスタンスグループ名 `worker` と一致させています）

## ライセンス

MIT
