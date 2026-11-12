#include "smc.h"
#include <string.h>
#include <unistd.h>
static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

// Direct charge inhibition. CHTE (ui32, 01000000 = inibita) has precedence when
// present: on M1 Pro firmware shipped with macOS 15.3.x CH0B/CH0C are still
// readable but writes are ignored (read-back stays 00 -> -15), while CHTE is the
// key that actually stops charging (same order as actuallymentor/battery).
// CH0B+CH0C (hex_ 02 = inibita) remain the fallback for older firmware.
static int key_shape(smc_conn_t c, const char *key, uint32_t n, uint32_t t) {
    uint8_t b[32]; uint32_t size=32, type=0;
    return smc_read(c,key,&type,b,&size)==0 && size==n && type==t;
}
int smc_charge_backend(smc_conn_t c) {
    if (key_shape(c,"CHTE",4,fourcc("ui32"))) return 2;
    if (key_shape(c,"CH0B",1,fourcc("hex_")) && key_shape(c,"CH0C",1,fourcc("hex_"))) return 1;
    return 0;
}
int smc_charge_paused(smc_conn_t c, int *paused) {
    if (!paused) return -1;
    const int backend=smc_charge_backend(c);
    uint8_t b[32]; uint32_t n=32;
    if (backend==1) {
        int r=smc_read(c,"CH0B",NULL,b,&n); if(r)return r;
        int first=b[0]!=0; n=32;
        r=smc_read(c,"CH0C",NULL,b,&n); if(r)return r;
        *paused=first || b[0]!=0; return 0;
    }
    if (backend==2) {
        int r=smc_read(c,"CHTE",NULL,b,&n); if(r)return r;
        *paused=b[0]!=0 || b[1]!=0 || b[2]!=0 || b[3]!=0; return 0;
    }
    return -14;
}
// -15 = write accepted but read-back differs (key ignored by this firmware).
static int write_verified(smc_conn_t c,const char *key,const uint8_t *value,uint32_t size) {
    uint8_t b[32]; uint32_t n=32;
    if (smc_read(c,key,NULL,b,&n)==0 && n==size && memcmp(value,b,size)==0) return 0; // already set
    int r=smc_write(c,key,value,size); if(r)return r;
    for (int i=0;i<3;i++) {
        if (i) usleep(50000);
        n=32; r=smc_read(c,key,NULL,b,&n); if(r)return r;
        if (n==size && memcmp(value,b,size)==0) return 0;
    }
    return -15;
}
int smc_charge_set_paused(smc_conn_t c, int paused) {
    if (paused!=0 && paused!=1) return -1;
    int backend=smc_charge_backend(c);
    if (backend==1) {
        uint8_t v=paused ? 2 : 0, zero=0;
        int a=write_verified(c,"CH0B",&v,1);
        int b=write_verified(c,"CH0C",&v,1);
        if (a || b) {
            // Best effort fail-open if either write/read-back fails.
            (void)write_verified(c,"CH0B",&zero,1);
            (void)write_verified(c,"CH0C",&zero,1);
            return a ? a : b;
        }
        return 0;
    }
    if (backend==2) {
        uint8_t v[4]={(uint8_t)paused,0,0,0}, zero[4]={0,0,0,0};
        int r=write_verified(c,"CHTE",v,4);
        if (r && paused) (void)write_verified(c,"CHTE",zero,4); // fail-open
        return r;
    }
    return -14;
}

// -1 = hold/no action, 0 = enable charging, 1 = inhibit charging.
int smc_charge_action(int limit, int percent, int ac, int paused) {
    if (limit<50 || limit>100 || percent<0 || percent>100) return -1;
    if (limit==100 || !ac) return paused ? 0 : -1;
    if (percent>=limit && !paused) return 1;
    if (percent<=limit-2 && paused) return 0;
    return -1;
}
