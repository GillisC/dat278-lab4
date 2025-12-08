#!/bin/bash
set -e

CC=${CC:-gcc}
CFLAGS="-O3 -std=c11 -Wall -Wextra -fno-tree-vectorize"

echo "Compiling kernels..."
$CC $CFLAGS img_preproc.c ../utils/helpers.c -o img_preproc
$CC $CFLAGS conv.c ../utils/helpers.c -o conv

LOG_VERSION=$1
echo
echo "Running kernel A (image preprocessing)..."
./img_preproc "$LOG_VERSION"

CONV_VERSION=$2

echo
echo "Running kernel B (convolution)..."
./conv "$CONV_VERSION"
