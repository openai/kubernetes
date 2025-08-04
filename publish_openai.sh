#!/usr/bin/env sh

set -euo pipefail

X=$1
Y=$2
Z=$3

if [ -z "$X" ] || [ -z "$Y" ] || [ -z "$Z" ]; then
    echo "Usage: $0 <X> <Y> <Z>"
    echo ""
    exit 1
fi

TAG="v1.$X.$Y-openai$Z"
ACTUAL_TAG=$(git describe --tags --exact-match)

# Tag should match git tag so the version injected into the binaries by k8s
# build process matches the name of the uploaded binaries
if [ "$TAG" != "$ACTUAL_TAG" ]; then
    echo "Tag mismatch: $TAG != $ACTUAL_TAG"
    echo "Ensure your commit is tagged with the version you are trying to upload"
    exit 1
fi

TARGETS=(
    kube-apiserver
    kube-controller-manager
    kube-scheduler
    kube-proxy
    kubelet
    kubectl
)

PLATFORMS=(
    linux/amd64
    linux/arm64
)

# One some older k8s versions the build image is not very good and doesn't include
# proper deps
# You may need to edit "build/build-image/Dockerfile" to include:
# RUN apt update && apt install -y gcc-x86-64-linux-gnu gcc-arm-linux-gnueabihf
export KUBE_BUILD_PLATFORMS="${PLATFORMS[@]}"
export KUBE_BUILD_CONFORMANCE=n

./build/run.sh make cross WHAT="${TARGETS[@]/#/cmd/}"

for PLATFORM in "${PLATFORMS[@]}"; do
    for TARGET in "${TARGETS[@]}"; do
        shasum -a 256 "_output/dockerized/bin/${PLATFORM}/${TARGET}"
        az storage blob upload \
            --account-name=oaiinfraartifacts \
            --container-name=artifacts \
            --name="kubernetes-release/release/${TAG}/bin/${PLATFORM}/${TARGET}" \
            --file="_output/dockerized/bin/${PLATFORM}/${TARGET}" \
            --overwrite \
            --auth-mode login
    done
done

# Reprint SHAs for convenience
for PLATFORM in "${PLATFORMS[@]}"; do
    for TARGET in "${TARGETS[@]}"; do
        shasum -a 256 "_output/dockerized/bin/${PLATFORM}/${TARGET}"
    done
done