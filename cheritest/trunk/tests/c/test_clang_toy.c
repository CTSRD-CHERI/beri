#include "assert.h"

__attribute__((noinline))
static int anotherTest(int spare)
{
	return 53;
}

int test(void)
{
	int a = 42;
	a += anotherTest(a);
	assert(a == 42+53);
	return 0;
}
