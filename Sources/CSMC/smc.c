// AppleSMC client: Apple Silicon arm64, read-only sensors and guarded helper writes.
#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

typedef struct { char major, minor, build, reserved[1]; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize; uint32_t dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVers vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static int valid_key(const char *key) { return key != NULL && strlen(key) == 4; }

int smc_open(smc_conn_t *conn) {
    if (!conn) return -1;
    *conn = 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -2;
    io_connect_t c = 0;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &c);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) return -3;
    *conn = (smc_conn_t)c;
    return 0;
}

void smc_close(smc_conn_t conn) { if (conn) IOServiceClose((io_connect_t)conn); }

static int smc_call(smc_conn_t conn, SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    kern_return_t kr = IOConnectCallStructMethod((io_connect_t)conn, KERNEL_INDEX_SMC,
                                                 in, sizeof(SMCKeyData), out, &outSize);
    if (kr != KERN_SUCCESS) return -10;
    if (out->result != 0) return -11; // key not found or SMC error
    return 0;
}

static int smc_keyinfo(smc_conn_t conn, const char *key, SMCKeyInfo *info) {
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    int r = smc_call(conn, &in, &out);
    if (r) return r;
    *info = out.keyInfo;
    return 0;
}

int smc_read(smc_conn_t conn, const char *key, uint32_t *type, uint8_t *buf, uint32_t *size) {
    if (!conn || !valid_key(key) || !buf || !size || *size < 32) return -1;
    SMCKeyInfo info;
    int r = smc_keyinfo(conn, key, &info);
    if (r) return r;
    if (info.dataSize > 32) return -12;
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    r = smc_call(conn, &in, &out);
    if (r) return r;
    memcpy(buf, out.bytes, info.dataSize);
    *size = info.dataSize;
    if (type) *type = info.dataType;
    return 0;
}

int smc_write(smc_conn_t conn, const char *key, const uint8_t *buf, uint32_t size) {
    if (!conn || !valid_key(key) || !buf || size == 0 || size > 32) return -1;
    SMCKeyInfo info;
    int r = smc_keyinfo(conn, key, &info);
    if (r) return r;
    if (info.dataSize != size) return -13;
    SMCKeyData in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = fourcc(key);
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.keyInfo.dataSize = size;
    memcpy(in.bytes, buf, size);
    return smc_call(conn, &in, &out);
}

int smc_read_number(smc_conn_t conn, const char *key, double *out) {
    uint8_t b[32]; uint32_t size = sizeof b, type = 0;
    int r = smc_read(conn, key, &type, b, &size);
    if (r) return r;
    if (type == fourcc("sp78") && size == 2) {
        *out = (double)(int16_t)((b[0] << 8) | b[1]) / 256.0;
    } else if (type == fourcc("flt ") && size == 4) {
        float f; memcpy(&f, b, 4); *out = f; // little-endian IEEE754 on arm64
    } else if (type == fourcc("fpe2") && size == 2) {
        *out = (double)((b[0] << 8) | b[1]) / 4.0;
    } else if ((type == fourcc("ui8 ") || type == fourcc("hex_")) && size == 1) {
        *out = b[0];
    } else if (type == fourcc("ui16") && size == 2) {
        *out = (b[0] << 8) | b[1];
    } else if (type == fourcc("ui32") && size == 4) {
        *out = (double)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3]);
    } else if (type == fourcc("si8 ") && size == 1) {
        *out = (int8_t)b[0];
    } else if (type == fourcc("si16") && size == 2) {
        *out = (int16_t)((b[0] << 8) | b[1]);
    } else {
        return -14;
    }
    return 0;
}

