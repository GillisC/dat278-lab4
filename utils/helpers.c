#include "helpers.h"
#include <stddef.h>
#include <stdlib.h>

// Flush CPU caches by reading/writing a large buffer
void flush_cache()
{
    static volatile char *flush_buffer = NULL;
    if (!flush_buffer)
    {
        flush_buffer = malloc(FLUSH_SIZE);
        if (!flush_buffer)
            return; // failed allocation
    }

    volatile char sink = 0;

    // Touch every cache line to evict old data
    for (size_t i = 0; i < FLUSH_SIZE; i += 64)
    { // 64B typical cache line
        flush_buffer[i] = (char)i;
        sink += flush_buffer[i];
    }

    // Prevent compiler from optimizing away
    (void)sink;
}