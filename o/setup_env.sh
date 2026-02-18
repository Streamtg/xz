#!/bin/bash
# SoniTranslate CentOS 7 Installer - Senior Edition
# No root required. Using Conda for binary isolation.

ENV_NAME="soni_pro"
CONDA_PATH=$(conda info --base)
source "$CONDA_PATH/etc/profile.d/conda.sh"

echo "❄️ Creando entorno con Python 3.10 y dependencias binarias..."
conda create -n $ENV_NAME python=3.10 ffmpeg libsndfile -c conda-forge -y

conda activate $ENV_NAME

echo "📦 Instalando dependencias de Python..."
# Instalamos PyTorch con soporte CUDA 11.8 (ideal para estabilidad en CentOS 7)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# SoniTranslate Core
git clone https://github.com/r3gm/SoniTranslate.git
cd SoniTranslate
pip install -r requirements_base.txt
pip install -r requirements_extra.txt
pip install yt-dlp edge-tts gradio

echo "✅ Entorno listo. Usa 'conda activate $ENV_NAME' para trabajar."
