#!/bin/bash

# exit if anything in the script fails
set -e 
# Source conda setup to ensure conda commands are available
eval "$(conda shell.bash hook)"

# for creating the conda environment
ENV_NAME="beesbook"

# Check if the Conda environment exists
if conda env list | grep -q "$ENV_NAME"; then
    echo "Conda environment '$ENV_NAME' already exists. Activating..."
else
    echo "Creating Conda environment '$ENV_NAME'..."
    conda create -n "$ENV_NAME" python=3.11 -y
fi

conda activate "$ENV_NAME"

# Install core Python packages if not already installed
echo "Installing core Python packages..."
conda install --yes python=3.11 
conda install --yes jupyterlab matplotlib scipy seaborn jupyter numpy
conda install --yes ffmpeg dill tqdm chardet
conda install --yes -c conda-forge cairocffi

if [[ "$OSTYPE" == "darwin"* ]]; then
    pip install --upgrade tensorflow
else
    pip install --upgrade tensorflow[and-cuda]
fi

# List of GitHub repositories and their package names, separated by a space
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

# Create a directory for model files in the conda environment
MODEL_DIR="$CONDA_PREFIX/pipeline_models"
mkdir -p $MODEL_DIR

# Download the model files if they don't already exist.  Also download the tracklet model file
if [ ! -f "$MODEL_DIR/decoder_2019_keras3.h5" ]; then
    wget -O $MODEL_DIR/decoder_2019_keras3.h5 "https://github.com/BioroboticsLab/bb_pipeline_models/blob/update/models/decoder/decoder_2019_keras3.h5?raw=true"
fi
if [ ! -f "$MODEL_DIR/localizer_2019_keras3.h5" ]; then
    wget -O $MODEL_DIR/localizer_2019_keras3.h5 "https://github.com/BioroboticsLab/bb_pipeline_models/blob/update/models/saliency/localizer_2019_keras3.h5?raw=true"
fi
if [ ! -f "$MODEL_DIR/localizer_2019_attributes.json" ]; then
    wget -O $MODEL_DIR/localizer_2019_attributes.json "https://github.com/BioroboticsLab/bb_pipeline_models/blob/update/models/saliency/localizer_2019_attributes.json?raw=true"
fi
if [ ! -f "$MODEL_DIR/detection_model_4.json" ]; then
    wget -O $MODEL_DIR/detection_model_4.json "https://github.com/BioroboticsLab/bb_pipeline_models/blob/update/models/tracking/detection_model_4.json?raw=true"
fi
if [ ! -f "$MODEL_DIR/tracklet_model_8.json" ]; then
    wget -O $MODEL_DIR/tracklet_model_8.json "https://github.com/BioroboticsLab/bb_pipeline_models/blob/update/models/tracking/tracklet_model_8.json?raw=true"
fi

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

# Install cuDNN if not already installed
if [ ! -f "$CONDA_PREFIX/lib/libcudnn.so" ]; then
    # Download the cuDNN package
    CUDNN_PKG="cudnn-linux-x86_64-8.9.6.50_cuda11-archive"
    wget "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/$CUDNN_PKG.tar.xz"
    tar -xvf "$CUDNN_PKG.tar.xz"

    # Move the extracted files to the conda environment
    cp "$CUDNN_PKG/include/"* $CONDA_PREFIX/include/.
    cp "$CUDNN_PKG/lib/"* $CONDA_PREFIX/lib/.

    # Cleanup
    rm -rf $CUDNN_PKG
    rm $CUDNN_PKG.tar.xz
fi

# Ensure the cuDNN libraries are found
mkdir -p $CONDA_PREFIX/etc/conda/activate.d
echo 'export PATH=$CONDA_PREFIX/bin:$PATH' > $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
echo 'export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh

echo "Installation and update completed."