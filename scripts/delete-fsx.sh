#!/bin/bash
#
# DRA(Data Repository Association) + FSx for Lustre 削除スクリプト
#
# 前提:
#   - HyperPod クラスタが削除済み(./scripts/delete-cluster.sh 実施後)
#     クラスタが残ったまま FSx を消そうとすると、クラスタからの利用中で
#     削除が失敗するため、必ず先にクラスタを削除すること
#
# 使い方:
#   ./scripts/delete-fsx.sh
#
# 削除順序:
#   1. DRA を削除(数分-10 分)
#   2. FSx を削除(10-20 分)
#
#   ※ DRA を残したまま FSx を消そうとするとエラーになるため、DRA を先に消す
#
# 注意:
#   - 削除完了まで合計 15-30 分かかります
#   - 削除完了をもって FSx 課金(約 1,200 円/日) が止まります
#

FSX_NAME="aws-hyperpod-slurm-hello-world-fsx"
REGION="ap-northeast-1"

# 1. Name タグから FSx ID を取得
FSX_ID=$(aws fsx describe-file-systems --region "${REGION}" \
  --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_NAME}']].FileSystemId" --output text)

if [ -z "${FSX_ID}" ]; then
  echo "[delete-fsx] 対象の FSx が見つかりません(既に削除済みの可能性)"
  exit 0
fi

# 2. 該当 FSx の DRA を列挙し、それぞれ削除完了まで待つ
DRA_IDS=$(aws fsx describe-data-repository-associations --region "${REGION}" \
  --filters Name=file-system-id,Values="${FSX_ID}" \
  --query 'Associations[?Lifecycle!=`DELETED`].AssociationId' --output text)

if [ -n "${DRA_IDS}" ]; then
  for DRA_ID in ${DRA_IDS}; do
    echo "[delete-fsx] DRA 削除要求送信: ${DRA_ID}"
    aws fsx delete-data-repository-association \
      --association-id "${DRA_ID}" \
      --delete-data-in-file-system \
      --region "${REGION}" >/dev/null

    # DRA 完全消失まで待機(通常 10-30 分)
    # 注意: 完全削除されると describe-data-repository-associations は
    # Associations: [] を返し、--query 'Associations[0].Lifecycle' は "None" 文字列になる
    # ため、DELETED / None / 空文字 すべてを削除完了と判定する
    while true; do
      STATUS=$(aws fsx describe-data-repository-associations --association-ids "${DRA_ID}" --region "${REGION}" \
        --query 'Associations[0].Lifecycle' --output text 2>/dev/null || echo "DELETED")
      echo "[delete-fsx] DRA ${DRA_ID} Status: ${STATUS}"
      case "${STATUS}" in
        DELETED|None|"") break ;;
        FAILED) echo "[delete-fsx] DRA 削除 FAILED"; exit 1 ;;
        *) sleep 30 ;;
      esac
    done
    echo "[delete-fsx] DRA 削除完了: ${DRA_ID}"
  done
else
  echo "[delete-fsx] DRA は存在しません(スキップ)"
fi

# 3. FSx 削除要求(非同期)
echo "[delete-fsx] FSx 削除要求送信: ${FSX_ID}"
aws fsx delete-file-system --file-system-id "${FSX_ID}" --region "${REGION}" >/dev/null

# 4. FSx 完全消失まで待機(通常 10-20 分)
while aws fsx describe-file-systems --file-system-ids "${FSX_ID}" --region "${REGION}" >/dev/null 2>&1; do
  echo "[delete-fsx] FSx 削除中..."
  sleep 30
done

echo "[delete-fsx] 完了"
