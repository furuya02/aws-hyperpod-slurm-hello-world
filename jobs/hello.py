# HyperPod 動作確認用ダミージョブ: GPU 認識と PyTorch import まで
import torch

cuda_available: bool = torch.cuda.is_available()
device_name: str = torch.cuda.get_device_name(0) if cuda_available else "cpu"

print(f"cuda.is_available: {cuda_available}")
print(f"device: {device_name}")
