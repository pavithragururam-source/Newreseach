FROM openroad/flow-ubuntu22.04-builder:latest

LABEL description="Quantum Echoes Placement-to-Compaction over ORFS"

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-pip python3-dev bc jq \
    && rm -rf /var/lib/apt/lists/*

COPY docker/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

ARG ORFS_COMMIT=a1b2c3d
RUN git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts /ORFS \
    && cd /ORFS && git checkout ${ORFS_COMMIT} \
    && git submodule update --init --recursive

WORKDIR /workspace
ENV ORFS_ROOT=/ORFS
ENV DESIGN_DIR=/workspace
ENV PYTHONPATH=/workspace/scripts
ENV PATH="${ORFS_ROOT}/tools/install/OpenROAD/bin:${PATH}"

CMD ["/bin/bash"]
