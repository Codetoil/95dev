#include <stdio.h>
#include <math.h>

int main(void) {
    printf("Hello, World!\n");
    volatile double x = 3.0;
    printf("%f\n", sqrt(x));
    return 0;
}
