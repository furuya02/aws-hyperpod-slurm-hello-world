#!/bin/bash
#
# AWS 公式の HyperPod 用 lifecycle スクリプト一式を lifecycle/ に取り込む
#
# 公式実装(awslabs/awsome-distributed-ai。旧 aws-samples/awsome-distributed-training)
# の base-config をまるごと取り込み、その上で本記事用の override
# (config.py.override / provisioning_parameters.json)だけ上書きする方針。
#
# Phase F(動作確認)に入る前に必ず一度実行してください。
#
# 使い方:
#   ./scripts/sync-lifecycle.sh
#

REPO="https://github.com/awslabs/awsome-distributed-ai.git"
SUBPATH="1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIFECYCLE_DIR="${REPO_ROOT}/lifecycle"
TMPDIR=$(mktemp -d)

# 浅いクローンで公式リポジトリを取得
git clone --depth 1 "${REPO}" "${TMPDIR}/awsome-distributed-ai"

# base-config 配下を lifecycle/ にコピー(.gitignore で git 管理外)
cp -r "${TMPDIR}/awsome-distributed-ai/${SUBPATH}/." "${LIFECYCLE_DIR}/"

# 本記事用 override を上書き
cp "${LIFECYCLE_DIR}/config.py.override" "${LIFECYCLE_DIR}/config.py"

rm -rf "${TMPDIR}"

# 取り込んだスクリプトに実行権限を付与
chmod +x "${LIFECYCLE_DIR}"/*.sh 2>/dev/null
chmod +x "${LIFECYCLE_DIR}"/utils/*.sh 2>/dev/null
