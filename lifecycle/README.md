# lifecycle/

HyperPod クラスタ起動時に各ノードで実行される lifecycle スクリプト一式を配置するディレクトリ。

## 構成方針

`on_create.sh` などの本体は **AWS Samples の [awsome-distributed-training](https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config) からそのまま取り込む** 設計。自前で持つのは下記の最小ファイルのみ。

| ファイル | 内容 | git 管理 |
|:--|:--|:--|
| `provisioning_parameters.json` | HyperPod インスタンスグループ定義(controller_group など)。自前で記述 | ✅ |
| `config.py.override` | AWS Samples の `config.py` を本記事用に最小化したオーバーライド版(全機能無効化、Slurm のみ) | ✅ |
| `on_create.sh` / `lifecycle_script.py` / `start_slurm.sh` / `utils/` 等 | AWS Samples から取り込み | ❌(`.gitignore`) |

## 使い方

1. リポジトリ直下で AWS Samples を取り込み: `./scripts/sync-lifecycle.sh`
2. `./scripts/create.sh` 実行(内部で S3 にアップロードされる)
