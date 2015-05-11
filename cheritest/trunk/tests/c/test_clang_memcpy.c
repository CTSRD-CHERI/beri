#include "assert.h"

typedef __SIZE_TYPE__ size_t;

// Currently, memcpy is called smemcpy.
#define memcpy smemcpy

__capability void *cmemcpy(__capability void *dst,
                           __capability const void *src,
                           size_t len);
void *memcpy(void *dst,
             const void *src,
             size_t len);
#define CAP(x) ((__capability void*)x)

// Test structure which will be memcpy'd.  Contains data and a capability in
// the middle.  The capability must be aligned, but memcpy should work for any
// partial copy of this structure that includes the capability, as long as both
// have the correct alignment.
struct Test 
{
	char pad0[32];
	__capability void *y;
	char pad1[32];
};

// Check that the copy has the data that we expect it to contain.  The start
// and end parameters describe the range in the padding to check.  For partial
// copies, the uncopied range will contain nonsense.
void check(struct Test *t1, int start, int end)
{
	for (int i=start ; i<32 ; i++)
	{
		assert(t1->pad0[i] == i);
	}
	assert((void*)t1->y == t1);
	assert(__builtin_cheri_get_cap_tag(t1->y));
	for (int i=0 ; i<end ; i++)
	{
		assert(t1->pad1[i] == i);
	}
}

// Write an obviously invalid byte pattern over the output structure.
void invalidate(struct Test *t1)
{
	unsigned char *x = (unsigned char*)t1;
	for (int i=0 ; i<sizeof(*t1) ; i++)
	{
		*x = 0xa5;
	}
}

// Run the memcpy tests
int test(void)
{
	struct Test t1, t2;
	invalidate(&t2);
	for (int i=0 ; i<32 ; i++)
	{
		t1.pad0[i] = i;
		t1.pad1[i] = i;
	}
	t1.y = CAP(&t2);
	invalidate(&t2);
	// Simple case: aligned start and end
	__capability void *cpy = cmemcpy(t1.y, CAP(&t1), sizeof(t1));
	assert((void*)cpy == &t2);
	check(&t2, 0, 32);
	invalidate(&t2);
	// Test that it still works with an unaligned start...
	cpy = cmemcpy(CAP(&t2.pad0[3]), CAP(&t1.pad0[3]), sizeof(t1) - 3);
	assert((void*)cpy == &t2.pad0[3]);
	check(&t2, 3, 32);
	// ...or an unaligned end...
	cpy = cmemcpy(CAP(&t2), CAP(&t1), sizeof(t1) - 3);
	assert((void*)cpy == &t2);
	check(&t2, 0, 29);
	// ...or both...
	cpy = cmemcpy(CAP(&t2.pad0[3]), CAP(&t1.pad0[3]), sizeof(t1) - 6);
	assert((void*)cpy == &t2.pad0[3]);
	check(&t2, 3, 29);
	invalidate(&t2);
	// ...and finally a case where the alignment is different for both?
	cpy = cmemcpy(CAP(&t2), CAP(&t1.pad0[1]), sizeof(t1) - 1);
	assert((void*)cpy == &t2);
	// This should have invalidated the capability
	assert(__builtin_cheri_get_cap_tag(t2.y) == 0);
	// Check that the non-capability data has been copied correctly
	for (int i=0 ; i<31 ; i++)
	{
		assert(t2.pad0[i] == i+1);
		assert(t2.pad1[i] == i+1);
	}
	invalidate(&t2);
	// Simple case: aligned start and end
	DEBUG_DUMP_REG(13, 1);
	void *copy = memcpy(&t2, &t1, sizeof(t1));
	assert(copy == &t2);
	check(&t2, 0, 32);
	invalidate(&t2);
	// Test that it still works with an unaligned start...
	DEBUG_DUMP_REG(13, 2);
	copy = memcpy(&t2.pad0[3], &t1.pad0[3], sizeof(t1) - 3);
	assert(copy == &t2.pad0[3]);
	check(&t2, 3, 32);
	DEBUG_DUMP_REG(13, 3);
	// ...or an unaligned end...
	copy = memcpy(&t2, &t1, sizeof(t1) - 3);
	assert(copy == &t2);
	check(&t2, 0, 29);
	DEBUG_DUMP_REG(13, 4);
	// ...or both...
	copy = memcpy(&t2.pad0[3], &t1.pad0[3], sizeof(t1) - 6);
	assert(copy == &t2.pad0[3]);
	check(&t2, 3, 29);
	invalidate(&t2);
	DEBUG_DUMP_REG(13, 5);
	// ...and finally a case where the alignment is different for both?
	copy = memcpy(&t2, &t1.pad0[1], sizeof(t1) - 1);
	assert(copy == &t2);
	// This should have invalidated the capability
	assert(!__builtin_cheri_get_cap_tag(t2.y));
	// Check that the non-capability data has been copied correctly
	for (int i=0 ; i<31 ; i++)
	{
		assert(t2.pad0[i] == i+1);
		assert(t2.pad1[i] == i+1);
	}
	return 0;
}

