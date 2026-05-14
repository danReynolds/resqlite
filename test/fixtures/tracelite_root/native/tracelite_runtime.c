#include "tracelite_runtime.h"

volatile int tlt_active = 0;

int tlt_attach(const char* explicit_path) {
  (void)explicit_path;
  return -1;
}

int tlt_register_producer(uint8_t kind, const char* process_name,
                          const char* thread_name) {
  (void)kind;
  (void)process_name;
  (void)thread_name;
  return -1;
}

uint32_t tlt_intern_string(const char* s, uint32_t len) {
  (void)s;
  (void)len;
  return 0xFFFFFFFFu;
}

void tlt_begin_on_track(uint8_t track_id, uint16_t span_id,
                        const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)span_id; (void)args; (void)arg_count;
}

void tlt_end_on_track(uint8_t track_id, uint16_t span_id,
                      const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)span_id; (void)args; (void)arg_count;
}

void tlt_begin_correlated_on_track(uint8_t track_id, uint16_t span_id,
                                   uint64_t correlation_id,
                                   const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)span_id; (void)correlation_id; (void)args;
  (void)arg_count;
}

void tlt_end_correlated_on_track(uint8_t track_id, uint16_t span_id,
                                 uint64_t correlation_id,
                                 const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)span_id; (void)correlation_id; (void)args;
  (void)arg_count;
}

void tlt_async_begin_on_track(uint8_t track_id, uint16_t span_id,
                              uint64_t correlation_id,
                              const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)span_id; (void)correlation_id; (void)args;
  (void)arg_count;
}

void tlt_async_end_on_track(uint8_t track_id, uint16_t span_id,
                            uint64_t correlation_id,
                            const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)span_id; (void)correlation_id; (void)args;
  (void)arg_count;
}

void tlt_counter_on_track(uint8_t track_id, uint16_t span_id, int64_t value) {
  (void)track_id; (void)span_id; (void)value;
}

void tlt_counter_correlated_on_track(uint8_t track_id, uint16_t span_id,
                                     uint64_t correlation_id, int64_t value) {
  (void)track_id; (void)span_id; (void)correlation_id; (void)value;
}

void tlt_metadata_on_track(uint8_t track_id, uint16_t metadata_kind,
                           const uint64_t* args, uint8_t arg_count) {
  (void)track_id; (void)metadata_kind; (void)args; (void)arg_count;
}

void tlt_detach_track(uint8_t track_id) {
  (void)track_id;
}
