#ifndef TBPOWER_SMC_H
#define TBPOWER_SMC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle (io_connect_t). 0 = not open.
typedef uint32_t smc_conn_t;

/// Returns 0 on success.
int smc_open(smc_conn_t *conn);
void smc_close(smc_conn_t conn);

/// Reads raw bytes of a 4-char key. On input *size = buffer capacity (>=32),
/// on output the key's data size. *type = 4-char data type (e.g. 'ui8 ').
int smc_read(smc_conn_t conn, const char *key, uint32_t *type, uint8_t *buf, uint32_t *size);

/// Writes raw bytes; size must match the key's declared size. Requires root.
int smc_write(smc_conn_t conn, const char *key, const uint8_t *buf, uint32_t size);

/// Reads a key and decodes it as a number (sp78, flt, fpe2, ui8/16/32, si8/16).
/// Returns 0 on success.
int smc_read_number(smc_conn_t conn, const char *key, double *out);

// 2 = CHTE (preferito); 1 = CH0B+CH0C; 0 = unsupported. No writes in detection/read.
int smc_charge_action(int limit, int percent, int ac, int paused);
int smc_charge_backend(smc_conn_t conn);
int smc_charge_paused(smc_conn_t conn, int *paused);
int smc_charge_set_paused(smc_conn_t conn, int paused);

#ifdef __cplusplus
}
#endif

#endif

