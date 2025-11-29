# Stage 1: Build image
FROM nvidia/cuda:13.0.2-devel-ubuntu24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Install build dependencies
# We explicitly install cuda-libraries-dev-13-0 (for libnpp-dev, etc.)
# AND cuda-cudart-dev-13-0 (for cuda_runtime.h and static linking)
# AND cuda-nvcc-13-0 (compiler) to ensure a complete toolchain.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    pkg-config \
    yasm \
    nasm \
    cmake \
    wget \
    curl \
    libtool \
    libc6-dev \
    unzip \
    ca-certificates \
    cuda-libraries-dev-13-0 \
    cuda-cudart-dev-13-0 \
    cuda-nvcc-13-0 \
    && apt-cache search cuda | grep headers && \
    rm -rf /var/lib/apt/lists/*

# Install nv-codec-headers
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make && \
    make install

# Download FFmpeg
WORKDIR /tmp/ffmpeg_build
RUN wget -O ffmpeg.tar.bz2 https://ffmpeg.org/releases/ffmpeg-7.1.3.tar.bz2 && \
    tar xjvf ffmpeg.tar.bz2

# Compile FFmpeg
# We use variables to ensure shell quoting is handled cleanly.
# We add -allow-unsupported-compiler to prevent errors with GCC 13 if nvcc is strict.
# Targets: Turing (75), Ampere (86), Ada (89).
RUN cd ffmpeg-7.1.3 && \
    nvcc --version && \
    ls -l /usr/local/cuda/include/npp.h && \
    (ls -l /usr/local/cuda/include/cuda.h || echo "cuda.h not found") && \
    NVCC_FLAGS="-gencode arch=compute_75,code=sm_75 -gencode arch=compute_86,code=sm_86 -gencode arch=compute_89,code=sm_89 -O2 -allow-unsupported-compiler" && \
    ./configure \
        --prefix=/usr/local \
        --enable-gpl \
        --enable-nonfree \
        --enable-cuda-nvcc \
        --enable-libnpp \
        --enable-cuvid \
        --enable-nvenc \
        --enable-nvdec \
        --extra-cflags="-I/usr/local/cuda/include" \
        --extra-ldflags="-L/usr/local/cuda/lib64" \
        --nvccflags="$NVCC_FLAGS" \
        --disable-doc \
        --disable-static \
        --enable-shared || (cat ffbuild/config.log && exit 1) && \
    make -j$(nproc) && \
    make install

# Stage 2: Runtime
FROM nvidia/cuda:13.0.2-runtime-ubuntu24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/cuda/bin:${PATH}

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-libraries-13-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy FFmpeg binaries and libraries
COPY --from=builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=builder /usr/local/bin/ffprobe /usr/local/bin/ffprobe
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include /usr/local/include

# Update library cache
RUN ldconfig

ENTRYPOINT ["ffmpeg"]
