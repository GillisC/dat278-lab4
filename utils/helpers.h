#define FLUSH_SIZE (32 * 1024 * 1024) // 32 MB
#define IMAGE_H 512
#define IMAGE_W 512
#define RUNS 100

#define FILTER_DIM 16 // must be <= IMAGE_H, IMAGE_W
// Flush CPU caches by reading/writing a large buffer
void flush_cache();