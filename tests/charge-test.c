// Pure mock protocol tests: never opens AppleSMC and performs no hardware writes.
#include "smc.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int pair=1, chte=1, fail_second=0, malformed=0, writes=0, ignore_pair=0;
static uint8_t a=0,b=0,t[4]={0};
static uint32_t cc(const char *s){return (uint32_t)s[0]<<24 | (uint32_t)s[1]<<16 | (uint32_t)s[2]<<8 | s[3];}
int smc_read(smc_conn_t c,const char *k,uint32_t *type,uint8_t *buf,uint32_t *n){
 (void)c;
 if(pair && (!strcmp(k,"CH0B") || !strcmp(k,"CH0C"))){
  *n=1;if(type)*type=cc(malformed?"ui8 ":"hex_");buf[0]=!strcmp(k,"CH0B")?a:b;return 0;}
 if(chte && !strcmp(k,"CHTE")){*n=4;if(type)*type=cc("ui32");memcpy(buf,t,4);return 0;}return -11;
}
int smc_write(smc_conn_t c,const char *k,const uint8_t *v,uint32_t n){
 (void)c;writes++;
 if(!strcmp(k,"CH0B")){assert(n==1);if(!ignore_pair)a=v[0];return 0;}
 if(!strcmp(k,"CH0C")){assert(n==1);if(fail_second && v[0]==2)return -10;b=v[0];return 0;}
 if(!strcmp(k,"CHTE")){assert(n==4);memcpy(t,v,4);return 0;}return -11;
}
int main(void){
 int p=-1;
 // Firmware M1 Pro/macOS 15.3: CHTE presente ha la precedenza su CH0B/CH0C.
 assert(smc_charge_backend(1)==2);assert(writes==0);
 assert(smc_charge_set_paused(1,1)==0 && t[0]==1 && a==0 && b==0);
 int w0=writes;assert(smc_charge_set_paused(1,1)==0 && writes==w0); // già impostata: nessuna scrittura
 assert(smc_charge_set_paused(1,0)==0 && t[0]==0);
 // Solo CH0B/CH0C, scrittura ignorata dal firmware: -15 e nessuna inibizione residua.
 chte=0;ignore_pair=1;assert(smc_charge_set_paused(1,1)==-15 && a==0 && b==0);ignore_pair=0;
 assert(smc_charge_backend(1)==1);
 assert(smc_charge_set_paused(1,1)==0 && a==2 && b==2);
 assert(smc_charge_paused(1,&p)==0 && p==1);
 assert(smc_charge_set_paused(1,0)==0 && a==0 && b==0);
 fail_second=1;assert(smc_charge_set_paused(1,1)!=0 && a==0 && b==0);fail_second=0;
 pair=0;chte=1;assert(smc_charge_backend(1)==2);
 assert(smc_charge_set_paused(1,1)==0 && t[0]==1 && t[1]==0 && t[2]==0 && t[3]==0);
 assert(smc_charge_set_paused(1,0)==0 && t[0]==0);
 chte=0;assert(smc_charge_backend(1)==0);int w=writes;assert(smc_charge_set_paused(1,1)!=0 && writes==w);
 pair=1;malformed=1;assert(smc_charge_backend(1)==0);
 assert(smc_charge_set_paused(1,2)!=0 && writes==w);
 assert(smc_charge_action(93,93,1,0)==1);
 assert(smc_charge_action(93,100,1,0)==1);
 assert(smc_charge_action(93,92,1,1)==-1);
 assert(smc_charge_action(93,91,1,1)==0);
 assert(smc_charge_action(93,90,1,0)==-1);
 assert(smc_charge_action(93,95,0,1)==0);
 assert(smc_charge_action(100,100,1,1)==0);
 assert(smc_charge_action(49,50,1,0)==-1);
 for(int limit=50;limit<=100;limit++)for(int pct=0;pct<=100;pct++)for(int ac=0;ac<=1;ac++)for(int paused=0;paused<=1;paused++){
  int expected=-1;
  if(limit==100 || !ac)expected=paused?0:-1;
  else if(pct>=limit && !paused)expected=1;
  else if(pct<=limit-2 && paused)expected=0;
  assert(smc_charge_action(limit,pct,ac,paused)==expected);
 }
 puts("OK: protocollo CH0B/CH0C/CHTE, rollback, tipi, isteresi, batteria/100%");return 0;
}
