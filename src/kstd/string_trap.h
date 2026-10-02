__attribute__((error("appendString: kernel string runtime")))
extern void appendString(void* s, void* x);

__attribute__((error("copyString: kernel string runtime")))
extern void copyString(void* dst, void* src);

__attribute__((error("nimToCStringConv: kernel string runtime")))
extern void* nimToCStringConv(void* s);

__attribute__((error("rawNewString: kernel string runtime")))
extern void* rawNewString(long len);

__attribute__((error("setLengthStr: kernel string runtime")))
extern void setLengthStr(void* s, long newLen);

__attribute__((error("prepareAdd: kernel string runtime")))
extern long prepareAdd(void* s, long addLen);

__attribute__((error("resizeString: kernel string runtime")))
extern void resizeString(void* s, long addLen);

__attribute__((error("rawNewSeq: kernel string runtime")))
extern void* rawNewSeq(long len);

__attribute__((error("setLengthSeq: kernel string runtime")))
extern void setLengthSeq(void* s, void* T, long newLen);
