# Dockerfile for serving dockers for transformers.
#
# To build:
# docker build -f model_oss/transformers/dockerfile/serve.Dockerfile . -t ${YOUR_IMAGE_TAG}
#
# To push to gcr:
# docker tag ${YOUR_IMAGE_TAG} gcr.io/${YOUR_PROJECT}/${YOUR_IMAGE_TAG}
# docker push gcr.io/${YOUR_PROJECT}/${YOUR_IMAGE_TAG}
# Switch to this base image for gpu serve.

FROM pytorch/torchserve:0.7.0-gpu

USER root

ENV infer_port=7080
ENV mng_port=7081
ENV model_name="transformers_serving"
ENV PATH="/home/model-server/:${PATH}"

# Install libraries.
ENV PIP_ROOT_USER_ACTION=ignore
RUN python3 -m pip install --upgrade pip
RUN pip install torch==1.13.1
RUN pip install torchvision==0.14.1
RUN pip install transformers==4.27.4
RUN pip install datasets==2.9.0
RUN pip install accelerate==0.17.0
RUN pip install triton==2.0.0.dev20221120
RUN pip install xformers==0.0.16
RUN pip install google-cloud-storage==2.7.0
RUN pip install absl-py==1.4.0

# Install libraries for document-question-answering.
RUN apt-get update
RUN apt-get install -y --no-install-recommends tesseract-ocr
RUN pip install tesseract==0.1.3
RUN pip install pytesseract==0.3.10

# Install tools.
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        wget \
        vim

# Copy license.
RUN wget https://raw.githubusercontent.com/GoogleCloudPlatform/vertex-ai-samples/main/LICENSE

# Copy model artifacts.
COPY model_oss/transformers/handler.py /home/model-server/handler.py
COPY model_oss/util/ /home/model-server/util/
ENV PYTHONPATH /home/model-server/

# Create torchserve configuration file.
RUN echo \
    "default_response_timeout=1800\n" \
    "service_envelope=json\n" \
    "inference_address=http://0.0.0.0:${infer_port}\n"  \
    "management_address=http://0.0.0.0:${mng_port}" >> /home/model-server/config.properties

# Expose ports.
EXPOSE ${infer_port}
EXPOSE ${mng_port}

# Archive model artifacts and dependencies.
# Do not set --model-file and --serialized-file because model and checkpoint will be dynamically loaded in handler.py.
RUN torch-model-archiver \
--model-name=${model_name} \
--version=1.0 \
--handler=/home/model-server/handler.py \
--runtime=python3 \
--export-path=/home/model-server/model-store \
--archive-format=default \
--force

# Run Torchserve HTTP serve to respond to prediction requests.
CMD ["torchserve", "--start", \
     "--ts-config", "/home/model-server/config.properties", \
     "--models", "${model_name}=${model_name}.mar", \
     "--model-store", "/home/model-server/model-store"]
