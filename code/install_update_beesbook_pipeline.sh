#!/bin/bash

# Exit if any command fails
set -e

# Source conda setup to ensure conda commands are available
eval "$(conda shell.bash hook)"

# Configuration
ENV_NAME="beesbook"
PYTHON_VERSION="3.12"
CUDA_VERSION="12.4.1"  #  should match the versions and be available on https://anaconda.org/nvidia/cuda-toolkit and https://anaconda.org/nvidia/cuda
CUDA_VERSION_SHORT="${CUDA_VERSION%.*}"  # Short format, e.g., 12.4, for PyTorch compatibility

# Check if the Conda environment exists
if conda env list | grep -q "$ENV_NAME"; then
    echo "Conda environment '$ENV_NAME' already exists. Activating..."
else
    echo "Creating Conda environment '$ENV_NAME' with Python $PYTHON_VERSION..."
    conda create -n "$ENV_NAME" python="$PYTHON_VERSION" -y
fi

conda activate "$ENV_NAME"

# Ensure pip is correctly installed in this Conda environment
conda install -n "$ENV_NAME" pip -y

# Install core Python packages
echo "Installing core Python packages..."
conda install --yes python="$PYTHON_VERSION"  # in case the environment already exists
conda install --yes jupyterlab matplotlib scipy seaborn jupyter numpy ffmpeg dill tqdm chardet
python -m pip install cairocffi  # install with pip because it's faster
conda install --yes -c conda-forge lapack blas sqlite

 
# Install TensorFlow
echo "Installing tensorflow"
if [[ "$OSTYPE" == "darwin"* ]]; then
    conda install -y pytorch::pytorch torchvision torchaudio -c pytorch
    conda install -y conda-forge::tensorflow
else
    # Install CUDA toolkit and cuDNN via conda
    echo "Installing CUDA Toolkit $CUDA_VERSION and compatible cuDNN version via conda..."
    conda install -y nvidia/label/cuda-"$CUDA_VERSION"::cuda
    conda install -y nvidia/label/cuda-"$CUDA_VERSION"::cuda-toolkit
    conda install -y nvidia::cudnn

    # Install PyTorch with specified CUDA version
    echo "Installing PyTorch with CUDA $CUDA_VERSION_SHORT..."
    conda install -y pytorch torchvision torchaudio pytorch-cuda="$CUDA_VERSION_SHORT" -c pytorch -c nvidia
    conda install -y conda-forge::tensorflow-gpu
fi

# List of GitHub repositories and their package names
REPOS=(
    "git+https://github.com/BioroboticsLab/bb_binary bb_binary"
    "git+https://github.com/BioroboticsLab/bb_pipeline bb_pipeline"
    "git+https://github.com/BioroboticsLab/bb_tracking bb_tracking"
    "git+https://github.com/BioroboticsLab/bb_behavior bb_behavior"
    "git+https://github.com/BioroboticsLab/bb_utils bb_utils"
)

# Install or update each repository and their dependencies
for repo in "${REPOS[@]}"; do
    # Split the string into URL and package name
    repo_url=$(echo "$repo" | awk '{print $1}')
    package_name=$(echo "$repo" | awk '{print $2}')
    # Uninstall the package
    python -m pip uninstall -y "$package_name"
    # Install or upgrade the package using pip
    python -m pip install --upgrade "$repo_url"
done

# Locate the bb_pipeline package directory
BB_PIPELINE_DIR=$(python -c "import pipeline; print('pipeline_path:'); print(pipeline.__path__[0])" | awk '/^pipeline_path:/{getline; print}')
CONFIG_FILE="$BB_PIPELINE_DIR/config.ini"

# Re-download the model files and overwrite if they exist
MODEL_DIR="$CONDA_PREFIX/pipeline_models"
mkdir -p $MODEL_DIR

# Download and replace model files
wget -O $MODEL_DIR/decoder_2019_keras3.h5 "https://github.com/BioroboticsLab/bb_pipeline_models/blob/master/models/decoder/decoder_2019_keras3.h5?raw=true"
wget -O $MODEL_DIR/localizer_2019_keras3.h5 "https://github.com/BioroboticsLab/bb_pipeline_models/blob/master/models/saliency/localizer_2019_keras3.h5?raw=true"
wget -O $MODEL_DIR/localizer_2019_attributes.json "https://github.com/BioroboticsLab/bb_pipeline_models/blob/master/models/saliency/localizer_2019_attributes.json?raw=true"
wget -O $MODEL_DIR/detection_model_4.json "https://github.com/BioroboticsLab/bb_pipeline_models/blob/master/models/tracking/detection_model_4.json?raw=true"
wget -O $MODEL_DIR/tracklet_model_8.json "https://github.com/BioroboticsLab/bb_pipeline_models/blob/master/models/tracking/tracklet_model_8.json?raw=true"

# Update pipeline/config.ini to point to local model files
if [[ "$OSTYPE" == "darwin"* ]]; then
    # MacOS
    sed -i '' "s|model_path=decoder_2019_keras3.h5|model_path=$MODEL_DIR/decoder_2019_keras3.h5|g" "$CONFIG_FILE"
    sed -i '' "s|model_path=localizer_2019_keras3.h5|model_path=$MODEL_DIR/localizer_2019_keras3.h5|g" "$CONFIG_FILE"
    sed -i '' "s|attributes_path=localizer_2019_attributes.json|attributes_path=$MODEL_DIR/localizer_2019_attributes.json|g" "$CONFIG_FILE"
else
    # Linux
    sed -i "s|model_path=decoder_2019_keras3.h5|model_path=$MODEL_DIR/decoder_2019_keras3.h5|g" $CONFIG_FILE
    sed -i "s|model_path=localizer_2019_keras3.h5|model_path=$MODEL_DIR/localizer_2019_keras3.h5|g" $CONFIG_FILE
    sed -i "s|attributes_path=localizer_2019_attributes.json|attributes_path=$MODEL_DIR/localizer_2019_attributes.json|g" $CONFIG_FILE
fi

echo "Installation and update completed."