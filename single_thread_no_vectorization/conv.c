// kernel_b.c
#define _POSIX_C_SOURCE 199309L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <assert.h>
#include <string.h>
#include "../utils/helpers.h"

static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

void convolution_baseline(
    const float *img,
    float *out,
    int height,
    int width,
    const float *kernel
)
{
    // Zero output first
    for (int y = 0; y < height; y++)
        for (int x = 0; x < width; x++)
            out[y * width + x] = 0.0f;

    // valid convolution region
    int out_h = height - FILTER_DIM + 1;
    int out_w = width - FILTER_DIM + 1;

    for (int y = 0; y < out_h; y++)
    {
        for (int x = 0; x < out_w; x++)
        {
            float acc = 0.0f;
            for (int ky = 0; ky < FILTER_DIM; ky++)
            {
                for (int kx = 0; kx < FILTER_DIM; kx++)
                {
                    acc += img[(y + ky) * width + (x + kx)] * kernel[ky * FILTER_DIM + kx];
                }
            }
            out[y * width + x] = acc;
        }
    }
}

#define MIN(a, b) ((a) < (b) ? (a) : (b))

void convolution_optimized(
    const float *img,
    float *out,
    int height,
    int width,
    const float *kernel)
{
    // Uses tiling to improve performance
    for (int y = 0; y < height; y++)
        for (int x = 0; x < width; x++)
            out[y * width + x] = 0.0f;

    int out_h = height - FILTER_DIM + 1;
    int out_w = width - FILTER_DIM + 1;

    const int BLOCK_SIZE = 64;
    const int BLOCKS = width / BLOCK_SIZE;

    for (int yy = 0; yy < out_h; yy += BLOCK_SIZE) {
        for (int xx = 0; xx < out_w; xx += BLOCK_SIZE) {

            int y_max = MIN(BLOCK_SIZE, out_h - yy);
            int x_max = MIN(BLOCK_SIZE, out_w - xx);

            for (int y = 0; y < y_max; y++) {
                for (int x = 0; x < x_max; x++) {
                    float acc = 0.0f;

                    for (int ky = 0; ky < FILTER_DIM; ky++) {
                        for (int kx = 0; kx < FILTER_DIM; kx++) {
                            acc += img[(yy + y + ky) * width + (xx + x + kx)] * kernel[ky * FILTER_DIM + kx];
                        }
                    }
                    out[(yy + y) * width + xx + x] = acc;

                }
            }
        }
    }

    // valid convolution region
}

int main(int argc, char **argv)
{
    float *img = (float *)malloc(sizeof(float) * IMAGE_H * IMAGE_W);
    float *out = (float *)malloc(sizeof(float) * IMAGE_H * IMAGE_W);
    float *kernel = (float *)malloc(sizeof(float) * FILTER_DIM * FILTER_DIM);

    if (!img || !out || !kernel)
    {
        fprintf(stderr, "Failed to allocate memory\n");
        free(img);
        free(out);
        free(kernel);
        return 1;
    }

    srand(123);

    // random image
    for (int y = 0; y < IMAGE_H; y++)
        for (int x = 0; x < IMAGE_W; x++)
            img[y * IMAGE_W + x] = ((float)rand() / RAND_MAX) * 255.0f;

    // random kernel
    for (int i = 0; i < FILTER_DIM * FILTER_DIM; i++)
        kernel[i] = ((float)rand() / RAND_MAX);

    double elapsed = 0.0;
    double checksum = 0.0;

    void (*conv_imp)(const float *, float *, int, int, const float *) = NULL;

    if (argc > 1)
    {
        if (strcmp(argv[1], "1") == 0)
        {
            printf("convolution_baseline\n");
            conv_imp = convolution_baseline;
        }
        else if (strcmp(argv[1], "2") == 0)
        {
            printf("convolution_optimized\n");
            conv_imp = convolution_optimized;
        }
        else
        {
            conv_imp = convolution_baseline; // default
        }
    }
    else
    {
        conv_imp = convolution_baseline; // default
    }

    for (int run = 0; run < RUNS; run++)
    {
        flush_cache();
        double t0 = now_sec();
        conv_imp(img, out, IMAGE_H, IMAGE_W, kernel); // convolution_imp1
        double t1 = now_sec();

        elapsed += t1 - t0;

        // checksum (first element of each row)
        for (int y = 0; y < IMAGE_H; y++)
            checksum += out[y * IMAGE_W];
    }

    elapsed /= RUNS;

    printf("Top-left aligned convolution (%dx%d) results:\n", FILTER_DIM, FILTER_DIM);
    printf("  checksum (row[0]) = %.3f\n", checksum);
    printf("  elapsed = %.6f ms\n", elapsed * 1000);
    int out_h = IMAGE_H - FILTER_DIM + 1;
    int out_w = IMAGE_W  - FILTER_DIM + 1;

    double flops = (double)out_h * out_w *
                FILTER_DIM * FILTER_DIM * 2.0;

    double gflops = flops / (elapsed * 1e9);

    printf("Image %dx%d | Filter %d | Avg GFLOP/s = %.2f\n",
        IMAGE_H, IMAGE_W, FILTER_DIM, gflops);
    assert(checksum > 834278140 && checksum < 834278160);

    free(img);
    free(out);
    free(kernel);
    return 0;
}
