# aws-hyperpod-slurm-hello-world

Amazon SageMaker HyperPod の最小構成（2 ノード: controller + worker）に FSx for Lustre 共有ストレージと DRA (Data Repository Association、`/fsx/jobs` ↔ S3 自動同期) を組み合わせて、Slurm hello world + GPU 認識テスト + `/fsx` マウント確認 + S3 自動エクスポート確認を実施するサンプル一式です。

## コスト警告（最重要）

HyperPod は **クラスタ起動中ずっと課金** されます（Training Job のような「ジョブ単位課金」ではありません）。FSx for Lustre も独立して秒単位で課金されます。DRA 自体は無課金です。

| 項目 | 値 |
|:--|:--|
| インスタンス | controller `ml.c5.xlarge` × 1 + worker `ml.g5.2xlarge` × 1（A10G 24GB） |
| 共有ストレージ | FSx for Lustre PERSISTENT_2 SSD, 1.2 TiB, 125 MB/s/TiB, **Lustre 2.15** |
| S3 連携 | DRA: `/fsx/jobs` ↔ `s3://...-lifecycle/jobs/`（AutoImport/AutoExport: NEW, CHANGED, DELETED）|
| 課金モード | On-Demand |
| 1 日放置のコスト | 約 **$68/日 ≒ 約 10,200 円/日**（worker 約 $53 + controller 約 $6 + FSx 約 $8 + NAT 約 $1.5） |
| 推奨運用 | 作成 → 即動作確認 → 即 `scripts/teardown.sh` |

**動作確認後は必ず `scripts/teardown.sh` を実行してください。** 削除順序が重要です（クラスタ → DRA → FSx → CDK スタック）。`teardown.sh` がこの順序を自動化します。

## 構成

| リソース | 命名 |
|:--|:--|
| VPC | `aws-hyperpod-slurm-hello-world-vpc`（プライベートサブネット 1 + NAT Gateway 1） |
| IAM Role | `aws-hyperpod-slurm-hello-world-execution-role` |
| S3 Bucket | `aws-hyperpod-slurm-hello-world-<account-id>-lifecycle`（lifecycle スクリプト配置 + DRA 連携先を兼用） |
| FSx 用 Security Group | `aws-hyperpod-slurm-hello-world-fsx-sg`（Lustre ポート 988, 1021-1023） |
| FSx for Lustre | `aws-hyperpod-slurm-hello-world-fsx`（`scripts/create-fsx.sh` で作成、CDK 外。Lustre 2.15 明示指定） |
| FSx DRA | `/fsx/jobs` ↔ `s3://aws-hyperpod-slurm-hello-world-<account-id>-lifecycle/jobs/`（`scripts/create-fsx.sh` が作成） |
| HyperPod クラスタ | `aws-hyperpod-slurm-hello-world`（2 InstanceGroups: controller `ml.c5.xlarge` × 1 / worker `ml.g5.2xlarge` × 1） |

## ディレクトリ構成

```
.
├── cdk/                          # AWS CDK (TypeScript): VPC / IAM / S3 / FsxSg + S3 bucket policy (FSx 用)
├── lifecycle/                    # HyperPod ノード起動時のセットアップ
│   ├── README.md
│   ├── provisioning_parameters.json  # version + worker_groups + controller_group + <FSX_*> プレースホルダ
│   └── config.py.override            # 自前(AWS Samples の config.py 上書き)
│   # 上記以外は scripts/sync-lifecycle.sh で awslabs/awsome-distributed-ai から取り込み
├── scripts/                      # 運用スクリプト
│   ├── sync-lifecycle.sh         # awslabs/awsome-distributed-ai の lifecycle 取り込み
│   ├── create-fsx.sh             # FSx for Lustre + DRA 作成(計 15-30 分待機)
│   ├── create.sh                 # クラスタ作成(クラスタ課金開始)
│   ├── connect.sh                # SSM Session Manager で controller に接続
│   ├── delete-cluster.sh         # クラスタのみ削除(動作確認の繰り返し用)
│   ├── delete-fsx.sh             # DRA -> FSx for Lustre の順に削除
│   └── teardown.sh               # クラスタ -> DRA -> FSx -> cdk destroy(順序付き完全削除)
├── jobs/                         # 動作確認用 Slurm ジョブ
│   ├── hello.py                  # 標準ライブラリのみ(hostname + /fsx + nvidia-smi via subprocess)
│   └── hello.sh                  # sbatch スクリプト(--output=/fsx/jobs/...)
├── cluster-config.json           # InstanceGroup 定義(プレースホルダ入り)
├── README.md
└── README.ja.md
```

## 前提

- AWS アカウントに以下のクォータがある（リージョン `ap-northeast-1`）:
  - HyperPod クラスタ: `ml.g5.2xlarge for cluster usage` >= 1（worker）+ `ml.c5.xlarge for cluster usage` >= 1（controller）
  - FSx for Lustre: SSD ストレージ容量クォータ >= 1228 GiB（1.2 TiB）
- ローカルに `aws` CLI / `pnpm` / Node.js 20+ / `git` / `jq` / Python 3 / Session Manager プラグインがインストール済み
- AWS 認証情報設定済み（`aws configure` または環境変数）

## 構築手順

```bash
# 1. リポジトリ取得
git clone https://github.com/furuya02/aws-hyperpod-slurm-hello-world.git
cd aws-hyperpod-slurm-hello-world

# 2. lifecycle スクリプト取り込み(awslabs/awsome-distributed-ai の base-config を lifecycle/ に展開)
./scripts/sync-lifecycle.sh

# 3. CDK 依存インストール
cd cdk
pnpm install

# 4. CDK ブートストラップ(初回のみ)
pnpm cdk bootstrap

# 5. CDK デプロイ(VPC / IAM / S3 / FsxSg + FSx 用 S3 bucket policy)
#    NAT 課金がここから発生(約 220 円/日)
pnpm cdk deploy

# 6. FSx for Lustre + DRA 作成(15-30 分待機)
#    FSx 課金が上乗せ(NAT 込み 約 1,400 円/日)
cd ..
./scripts/create-fsx.sh

# 7. クラスタ作成。クラスタ課金が上乗せ(合計 約 10,200 円/日)
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

# FSx for Lustre のマウント確認
mount | grep fsx
srun -N1 bash -c 'mount | grep fsx'
mkdir -p /fsx/jobs
echo "hello" > /fsx/jobs/test.txt
srun -N1 cat /fsx/jobs/test.txt   # "hello" が出れば worker からも /fsx が見えている

# DRA 経由の S3 自動 export 確認(数秒-数分後)
aws s3 ls s3://aws-hyperpod-slurm-hello-world-<ACCOUNT_ID>-lifecycle/jobs/

# hello ジョブ実行(/fsx/jobs/ に hello.py / hello.sh を配置してから)
# 注意: sbatch の stdout が空になる場合あり。srun が確実
srun -N1 python3 /fsx/jobs/hello.py
```

## 削除（必須）

```bash
./scripts/teardown.sh
```

`teardown.sh` は順序付きで以下を実行します。

1. `delete-cluster.sh` — HyperPod クラスタ削除完了まで待機（10-15 分）
2. `delete-fsx.sh` — **DRA を先に削除** → FSx for Lustre を削除（合計 25-45 分）
3. `pnpm cdk destroy --all --force` — VPC / NAT / IAM / S3 / FsxSg（3-5 分）

順序が重要です:

- FSx を先に消そうとするとクラスタ利用中で失敗
- DRA を残したまま FSx を消そうとすると DRA がまだ参照中で失敗
- FSx 残置で `cdk destroy` すると ENI 残留で VPC 削除失敗 → NAT 課金が止まらない

完了後、AWS Cost Explorer で当日 / 翌日の SageMaker / EC2 / FSx 料金が 0 円になっていることを必ず確認してください。

## 注意事項

- 本サンプルはエラーハンドリングを最小化しています。本番利用は想定していません
- `lifecycle/` 配下に `scripts/sync-lifecycle.sh` で取り込んだファイルは git 管理外（`.gitignore`）です
- Slurm の役割を 2 ノードに分離する設計です（controller: `ml.c5.xlarge` / compute: `ml.g5.2xlarge`）。`lifecycle_script.py` は自ノードのインスタンスグループ名を `provisioning_parameters.json` の `controller_group` と照合し、一致すれば controller、それ以外は compute と判定する排他ロジックのため、両者を 1 つのインスタンスグループに同居させることはできません
- FSx for Lustre + DRA は教育的観点で **CDK の外** に出しています（VPC+NAT → +FSx → +クラスタの 3 段階で課金フェーズを観察できる構成）。代償として「FSx 消し忘れで 約 1,200 円/日 漏れる」リスクが増えるため、`teardown.sh` の順序付き削除を必ず使ってください
- DRA セットアップは AWS CLI (`aws fsx create-data-repository-association`) で実装しています。kit は Lambda カスタムリソースで自動化していますが、本記事は CLI 直叩きの軽量実装としています。同じ API を呼んでいるだけなので機能差はなく、CDK スタック更新時の自動追従はないトレードオフ
- lifecycle 取得元: `awslabs/awsome-distributed-ai`（2026 年 5 月に `aws-samples/awsome-distributed-training` から rename + transfer されたもの）
- HyperPod DLAMI には **PyTorch / Python ML フレームワークは含まれません**。NVIDIA ドライバ + CUDA のみ。同梱の `hello.py` は PyTorch 非依存（`nvidia-smi` の subprocess 呼び出し）にしています

## ライセンス

MIT
