#ifndef TRACELITE_FIXTURE_RUNTIME_H
#define TRACELITE_FIXTURE_RUNTIME_H

#include <stdint.h>

#define TLT_TRACK_KIND_ISOLATE 1
#define TLT_TRACK_KIND_C_THREAD 2

extern volatile int tlt_active;

int tlt_attach(const char* explicit_path);
int tlt_register_producer(uint8_t kind, const char* process_name,
                          const char* thread_name);
uint32_t tlt_intern_string(const char* s, uint32_t len);
void tlt_begin_on_track(uint8_t track_id, uint16_t span_id,
                        const uint64_t* args, uint8_t arg_count);
void tlt_end_on_track(uint8_t track_id, uint16_t span_id,
                      const uint64_t* args, uint8_t arg_count);
void tlt_begin_correlated_on_track(uint8_t track_id, uint16_t span_id,
                                   uint64_t correlation_id,
                                   const uint64_t* args, uint8_t arg_count);
void tlt_end_correlated_on_track(uint8_t track_id, uint16_t span_id,
                                 uint64_t correlation_id,
                                 const uint64_t* args, uint8_t arg_count);
void tlt_async_begin_on_track(uint8_t track_id, uint16_t span_id,
                              uint64_t correlation_id,
                              const uint64_t* args, uint8_t arg_count);
void tlt_async_end_on_track(uint8_t track_id, uint16_t span_id,
                            uint64_t correlation_id,
                            const uint64_t* args, uint8_t arg_count);
void tlt_counter_on_track(uint8_t track_id, uint16_t span_id, int64_t value);
void tlt_counter_correlated_on_track(uint8_t track_id, uint16_t span_id,
                                     uint64_t correlation_id, int64_t value);
void tlt_metadata_on_track(uint8_t track_id, uint16_t metadata_kind,
                           const uint64_t* args, uint8_t arg_count);
void tlt_detach_track(uint8_t track_id);

#endif
