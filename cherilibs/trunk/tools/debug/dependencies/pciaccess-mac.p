--- lib/libpciaccess/src/common_interface.c-orig	2007-11-03 13:39:47.000000000 +0100
+++ lib/libpciaccess/src/common_interface.c	2008-02-23 14:51:13.000000000 +0100
@@ -57,6 +57,14 @@
 #define	LETOH_32(x)	(x)
 #define	HTOLE_32(x)	(x)
 
+#elif defined(__APPLE__) /* Mac OS X */
+#include <machine/endian.h>
+#include <libkern/OSByteOrder.h>
+#define	LETOH_16(x)	OSSwapLittleToHostInt16(x)
+#define	HTOLE_16(x)	OSSwapHostToLittleInt16(x)
+#define	LETOH_32(x)	OSSwapLittleToHostInt32(x)
+#define	HTOLE_32(x)	OSSwapHostToLittleInt32(x)
+
 #else
 
 #include <sys/endian.h>
