# HyperPod 動作確認用ダミージョブ
# 標準ライブラリのみ(PyTorch 等の追加インストール不要)で
#   - 実行ホスト名
#   - /fsx の共有ストレージ可視性
#   - GPU 認識(nvidia-smi)
# を出力する。
import os
import socket
import subprocess


def main() -> None:
    print(f"hostname: {socket.gethostname()}")

    if os.path.exists("/fsx"):
        entries = os.listdir("/fsx")
        print(f"/fsx mounted: {entries}")
    else:
        print("/fsx not mounted")

    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            check=True,
        )
        print(f"gpu: {result.stdout.strip()}")
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        print(f"gpu: not available ({e})")


if __name__ == "__main__":
    main()
