// kernel_b.c
#define _POSIX_C_SOURCE 199309L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <assert.h>
#include <string.h>
#include <arm_neon.h>
#include <omp.h>
#include "../utils/helpers.h"

static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

void preproc_baseline(
    float *img,
    float *mask1,
    float *mask2,
    int height,
    int width)
{
    for (int x = 0; x < width; x++)
    {
        float sum_of_col = 0.0;
        for (int y = 0; y < height; y++)
        {
            sum_of_col += img[y * width + x];
        }
        sum_of_col /= height;
        float rec = 1.0 / sum_of_col;
        for (int y = 0; y < height; y++)
        {
            float norm = img[y * width + x] * rec;
            img[y * width + x] = norm + mask1[y * width + x] - mask2[y * width + x];
            mask1[y * width + x] -= norm;
            mask2[y * width + x] += norm;
        }
    }
}

void preproc_optimized(
    float *img,
    float *mask1,
    float *mask2,
    int height,
    int width)
{
}

int main(int argc, char **argv)
{
    float *img = (float *)malloc(sizeof(float) * IMAGE_H * IMAGE_W);
    float *mask1 = (float *)malloc(sizeof(float) * IMAGE_H * IMAGE_W);
    float *mask2 = (float *)malloc(sizeof(float) * IMAGE_H * IMAGE_W);

    if (!img)
    {
        fprintf(stderr, "Failed to allocate memory\n");
        free(img);
        return 1;
    }

    srand(123);

    for (int y = 0; y < IMAGE_H; y++)
    {
        for (int x = 0; x < IMAGE_W; x++)
        {
            img[y * IMAGE_W + x] = ((float)rand() / RAND_MAX) * 255.0f;
            mask1[y * IMAGE_W + x] = ((float)rand() / RAND_MAX) * 255.0f;
            mask2[y * IMAGE_W + x] = ((float)rand() / RAND_MAX) * 255.0f;
        }
    }

    double elapsed = 0.0;
    double checksum = 0.0;

    void (*preproc_imp)(float *, float *, float *, int, int) = NULL;

    if (argc > 1)
    {
        if (strcmp(argv[1], "1") == 0)
        {
            printf("preproc_baseline\n");
            preproc_imp = preproc_baseline;
        }
        else if (strcmp(argv[1], "2") == 0)
        {
            printf("preproc_optimized\n");
            preproc_imp = preproc_optimized;
        }
        else
        {
            preproc_imp = preproc_baseline; // default
        }
    }
    else
    {
        preproc_imp = preproc_baseline; // default
    }

    for (int run = 0; run < RUNS; run++)
    {
        flush_cache();
        double t0 = now_sec();
        preproc_imp(img, mask1, mask2, IMAGE_H, IMAGE_W); // preproc_baseline
        double t1 = now_sec();

        elapsed += t1 - t0;

        // checksum (first element of each row)
        for (int y = 0; y < IMAGE_H; y++)
            checksum += img[y * IMAGE_W];
    }

    elapsed /= RUNS;

    printf("  checksum (row[0]) = %.3f\n", checksum);
    double flops = 6.0 * IMAGE_W * IMAGE_H; // approximate total FLOPs
    double gflops = flops / (elapsed * 1e9);
    printf("Image %dx%d | Avg GFLOP/s = %.2f\n",
           IMAGE_H, IMAGE_W, gflops);
    printf("  elapsed = %.6f ms\n", elapsed * 1000);
    assert(checksum > -5368876 && checksum < -5368875);

    free(img);
    free(mask1);
    free(mask2);
    return 0;
}
