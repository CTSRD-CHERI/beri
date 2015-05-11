
__attribute__((noreturn)) int __assert_fail(int);
void  __assert(int cond, int line)
{
	if (!cond)
	{
		__assert_fail(line);
	}
}
#define assert(cond) __assert(cond, __LINE__)

// Dumps a value into a specified register.  Useful for debugging test cases.
#define DEBUG_DUMP_REG(regno, val) \
    __asm__ volatile ("dadd $" #regno ", %0, $0" : : "r" (val) : #regno);

// Add a nop
#define DEBUG_NOP() \
	__asm__ volatile ("nop")

