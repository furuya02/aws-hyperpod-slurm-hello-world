#!/bin/bash
#SBATCH --job-name=hello
#SBATCH --output=/fsx/jobs/hello.%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1

# /fsx/jobs/ は FSx for Lustre 経由で S3(s3://...lifecycle/jobs/)に自動 export される
# (DRA: AutoExportPolicy=NEW,CHANGED,DELETED)
mkdir -p /fsx/jobs
cd /fsx/jobs
python3 hello.py
