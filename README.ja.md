# aws-hyperpod-slurm-hello-world

Amazon SageMaker HyperPod の最小構成（2 ノード: controller + worker）で Slurm hello world と GPU 認識テストを実施するためのサンプル一式です。

## コスト警告（最重要）

HyperPod は **クラスタ起動中ずっと課金** されます（Training Job のような「ジョブ単位課金」ではありません）。

| 項目 | 値 |
|:--|:--|
| インスタンス | controller `ml.c5.xlarge` × 1 + worker `ml.g5.2xlarge` × 1（A10G 24GB） |
| 課金モード | On-Demand |
| 1 日放置のコスト | 約 **$59/日 ≒ 約 8,800 円/日**（worker 約 $53 + controller 約 $6） |
| 推奨運用 | 作成 → 即動作確認 → 即 `scripts/teardown.sh` |

**動作確認後は必ず `scripts/teardown.sh` を実行してください。**

## 構成

| リソース | 命名 |
|:--|:--|
| VPC | `aws-hyperpod-slurm-hello-world-vpc`（プライベートサブネット 1 + NAT Gateway 1） |
| IAM Role | `aws-hyperpod-slurm-hello-world-execution-role` |
| S3 Bucket | `aws-hyperpod-slurm-hello-world-<account-id>-lifecycle` |
| HyperPod クラスタ | `aws-hyperpod-slurm-hello-world`（2 InstanceGroups: controller `ml.c5.xlarge` × 1 / worker `ml.g5.2xlarge` × 1） |

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

- AWS アカウントに HyperPod クラスタ用クォータが両方 1 以上ある（リージョン `ap-northeast-1`）: `ml.g5.2xlarge for cluster usage`（worker）と `ml.c5.xlarge for cluster usage`（controller）
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

# 6. クラスタ作成(ここから HyperPod 2 ノードの課金開始: 合計 約 $59/日)
cd ..
./scripts/create.sh
```

## 動作確認

```bash
# SSM Session Manager で controller ノードに接続
./scripts/connect.sh

# (以降は controller ノード内。srun は worker へジョブを投げる)
sinfo                  # Slurm クラスタ状態
srun -N1 hostname      # シンプル実行
srun -N1 nvidia-smi    # GPU 認識確認(worker の A10G が見える)

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
- Slurm の役割を 2 ノードに分離する設計です（controller: `ml.c5.xlarge` / compute: `ml.g5.2xlarge`）。`lifecycle_script.py` は自ノードのインスタンスグループ名を `provisioning_parameters.json` の `controller_group` と照合し、一致すれば controller、それ以外は compute と判定する排他ロジックのため、両者を 1 つのインスタンスグループに同居させることはできません

## ライセンス

MIT
