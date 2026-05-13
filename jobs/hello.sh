#!/bin/bash
#SBATCH --job-name=hello
#SBATCH --output=hello.%j.out
#SBATCH --nodes=1
#SBATCH --ntasks=1

python hello.py
