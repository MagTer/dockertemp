# NVIDIA FFmpeg Docker Container

This Dockerfile creates a container with FFmpeg 7.1 compiled with full NVIDIA hardware acceleration support (NVENC, NVDEC, CUDA filters) on Ubuntu 24.04 and CUDA 13.0.2.

## Requirements

*   **NVIDIA GPU**: A supported NVIDIA GPU (Turing or newer recommended).
    *   **Note**: CUDA 13.0 dropped support for Maxwell (50), Pascal (60), and Volta (70) architectures.
    *   **Targeted Architectures**: This image is optimized for Turing (RTX 20-series), Ampere (RTX 30-series), and Ada Lovelace (RTX 40-series).
*   **NVIDIA Driver**: A recent NVIDIA driver installed on the host system compatible with CUDA 13.0 (Driver version >= 550 recommended).
*   **Docker**: Docker Engine installed.
*   **NVIDIA Container Toolkit**: This is **crucial**. You must install the NVIDIA Container Toolkit on your host machine to allow Docker containers to access the GPU.
    *   Installation Guide: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html

## Building the Image

Run the following command in the directory containing the `Dockerfile`:

```bash
docker build -t ffmpeg-cuda .
```

## Running the Container

To use the GPU inside the container, you must pass the `--gpus all` flag (or specify specific GPUs).

### Basic Test (Check for CUDA support)
```bash
docker run --rm --gpus all ffmpeg-cuda -version
```
You should see configuration flags including `--enable-cuda-nvcc`, `--enable-libnpp`, etc.

### Check Available CUDA Filters
```bash
docker run --rm --gpus all ffmpeg-cuda -filters | grep cuda
```
Output should include `scale_cuda`, `tonemap_cuda`, `overlay_cuda`, etc.

### Check Available Encoders
```bash
docker run --rm --gpus all ffmpeg-cuda -encoders | grep nvenc
```

### Example: Transcoding with Hardware Acceleration
This example maps the current directory (`$(pwd)`) to `/data` inside the container.

```bash
docker run --rm --gpus all -v $(pwd):/data ffmpeg-cuda \
    -hwaccel cuda \
    -hwaccel_output_format cuda \
    -i /data/input.mp4 \
    -c:v h264_nvenc \
    -preset p4 \
    -cq 20 \
    /data/output.mp4
```

### Example: Tone Mapping (HDR to SDR)
```bash
docker run --rm --gpus all -v $(pwd):/data ffmpeg-cuda \
    -hwaccel cuda \
    -hwaccel_output_format cuda \
    -i /data/input_hdr.mkv \
    -vf "tonemap_cuda=format=p010" \
    -c:v h264_nvenc \
    /data/output_sdr.mp4
```

## Notes on Alpine Linux
The user requested an Alpine Linux version if possible. Currently, NVIDIA does not provide official CUDA base images for Alpine Linux due to its use of `musl` libc instead of `glibc`, which the proprietary NVIDIA drivers depend on. While there are unsupported workarounds (like installing `gcompat`), they are unstable for complex GPU tasks like video transcoding. Ubuntu 24.04 (used here) offers the best stability and official support for CUDA 13.

## Image Size Optimization
This Dockerfile uses a **multi-stage build**.
1.  **Builder Stage**: Uses the large `devel` image with compilers and headers to build FFmpeg.
2.  **Runtime Stage**: Uses the smaller `runtime` image and only copies the resulting binaries and necessary libraries.
This significantly reduces the final image size compared to a single-stage build.

## CI/CD Pipeline

This repository includes a GitHub Actions workflow (`.github/workflows/docker-build.yml`) that automatically:
1.  Builds the Docker image on every push to ensure the `Dockerfile` is valid.
2.  Runs sanity checks on the built image to verify:
    *   FFmpeg configuration flags (CUDA, NPP, NVENC).
    *   Presence of `tonemap_cuda` and `scale_npp` filters.
    *   Presence of NVENC encoders.

*Note: The CI pipeline runs on CPU-only runners. It verifies the build and binary capabilities, but cannot execute actual GPU transcoding tasks.*
