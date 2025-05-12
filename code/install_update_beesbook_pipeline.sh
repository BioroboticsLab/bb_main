#!/bin/bash
# Exit on any error
set -e

# Make sure conda is available
eval "$(conda shell.bash hook)"

### Configuration ###
ENV_NAME="beesbook"
PYTHON_VERSION="3.12"

# Update to latest CUDA supported by PyTorch (2.7.0): CUDA 12.8
CUDA_VERSION="12.8"
CUDA_VERSION_SHORT="${CUDA_VERSION}"

### Create or activate env ###
if conda env list | grep -q "^${ENV_NAME} "; then
  echo "Activating existing environment '$ENV_NAME'…"
else
  echo "Creating environment '$ENV_NAME' with Python $PYTHON_VERSION…"
  conda create -n "$ENV_NAME" python="$PYTHON_VERSION" -y
fi
conda activate "$ENV_NAME"

### Core tooling ###
conda install -y pip
python -m pip install --upgrade pip
python -m pip cache purge
echo "Installing core Python packages…"
conda install -y \
  jupyterlab matplotlib scipy seaborn numpy ffmpeg dill tqdm chardet \
  -c conda-forge
python -m pip install cairocffi
conda install -y -c conda-forge lapack blas sqlite

### TensorFlow ###
echo "Installing TensorFlow (with GPU support if available)…"
conda install -y -c conda-forge tensorflow
### PyTorch ###
echo "Installing PyTorch 2.x "
if [[ "$OSTYPE" == "darwin"* ]]; then
  python -m pip install torch torchvision torchaudio
else
  python -m pip install \
    --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cu128 \
    torch torchvision torchaudio  
fi



### Your BB packages ###
REPOS=(
  "git+https://github.com/BioroboticsLab/bb_binary bb_binary"
  "git+https://github.com/BioroboticsLab/bb_pipeline bb_pipeline"
  "git+https://github.com/BioroboticsLab/bb_tracking bb_tracking"
  "git+https://github.com/BioroboticsLab/bb_behavior bb_behavior"
  "git+https://github.com/BioroboticsLab/bb_utils bb_utils"
)
echo "Installing/updating BB packages…"
for entry in "${REPOS[@]}"; do
  url=${entry%% *}
  pkg=${entry##* }
  python -m pip uninstall -y "$pkg"
  python -m pip install --upgrade "$url"
done

### Model files ###
BB_PIPELINE_DIR=$(python -c "import pipeline; print(pipeline.__path__[0])")
CONFIG_FILE="$BB_PIPELINE_DIR/config.ini"
MODEL_DIR="$CONDA_PREFIX/pipeline_models"
mkdir -p "$MODEL_DIR"

echo "Downloading model files…"
for f in \
  decoder_2019_keras3.h5 \
  localizer_2019_keras3.h5 \
  localizer_2019_attributes.json \
  detection_model_4.json \
  tracklet_model_8.json
do
  wget -q -O "$MODEL_DIR/$f" \
    "https://raw.githubusercontent.com/BioroboticsLab/bb_pipeline_models/master/models/${f//_keras3.h5/decoder/}${f}"
done

echo "Patching config.ini…"
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' \
    -e "s|model_path=.*\.h5|model_path=$MODEL_DIR/decoder_2019_keras3.h5|" \
    -e "s|model_path=.*localizer_2019_keras3.h5|model_path=$MODEL_DIR/localizer_2019_keras3.h5|" \
    -e "s|attributes_path=.*\.json|attributes_path=$MODEL_DIR/localizer_2019_attributes.json|" \
    "$CONFIG_FILE"
else
  sed -i \
    -e "s|model_path=.*\.h5|model_path=$MODEL_DIR/decoder_2019_keras3.h5|" \
    -e "s|model_path=.*localizer_2019_keras3.h5|model_path=$MODEL_DIR/localizer_2019_keras3.h5|" \
    -e "s|attributes_path=.*\.json|attributes_path=$MODEL_DIR/localizer_2019_attributes.json|" \
    "$CONFIG_FILE"
fi

### Fix sklearn/xgboost and other issues ###
echo "Ensuring compatible scikit-learn & xgboost…"
python -m pip uninstall -y scikit-learn xgboost
conda clean --all -y
conda install -y -c conda-forge \
  scikit-learn=1.5.2 xgboost
conda install -y -c conda-forge libgfortran=3  

echo "Installation/update complete."