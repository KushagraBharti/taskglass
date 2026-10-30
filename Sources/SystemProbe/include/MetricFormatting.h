#pragma once
#include <stdio.h>
#include <xlocale.h>

// Keep fixed-precision readings in the C locale, matching the app's existing
// unlocalized decimal labels. The wrapper avoids Foundation varargs boxing.
static inline int tg_format_decimal(char *buffer, size_t capacity, double value, int places) {
    return snprintf_l(buffer, capacity, NULL, "%.*f", places, value);
}
