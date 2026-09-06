// Verification fixture for the ELF-to-DataMem loader.
// Volatile forces GCC to execute real loads instead of replacing the sum with 31.
volatile unsigned values[5] = {1, 2, 4, 8, 16};

int main(void)
{
    return values[0] + values[1] + values[2] + values[3] + values[4];
}
