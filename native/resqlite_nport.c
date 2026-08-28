// EXP-279 prototype (moonshot): native-thread dispatch with native-port
// completion.
//
// The question this file exists to answer is whether keeping SQLite off the
// calling isolate actually requires a *Dart* isolate. Today every read costs a
// `SendPort` round trip (exp 265 priced it at 6.3 us of an 8.4 us point read),
// and exps 265/269/270/275 each failed to collect that headroom while keeping
// the safety the hop buys. A POSIX thread holding a C reader slot offers the
// same isolation from the caller's event loop; the open question is what the
// completion costs when it arrives from a native thread through
// `Dart_PostCObject_DL` instead of from a worker isolate through a `SendPort`.
//
// Compiled only when hook/build.dart defines RESQLITE_NPORT, which it does when
// the Dart SDK's include/ directory (dart_api_dl) is resolvable. Nothing in
// lib/ links against it: the symbols here are prototype/test-only.
#ifdef RESQLITE_NPORT

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "dart_api_dl.h"
#include "resqlite.h"

#if defined(_WIN32)
#error "RESQLITE_NPORT prototype is POSIX-only"
#endif

#include <pthread.h>

// ---------------------------------------------------------------------------
// Dart API DL bootstrap
// ---------------------------------------------------------------------------

// Resolves Dart_PostCObject_DL and friends from the VM's symbol table. Must be
// called once, from Dart, with `NativeApi.initializeApiDLData`, before any post
// below. Returns 0 on success.
intptr_t resqlite_nport_init(void* data) { return Dart_InitializeApiDL(data); }

static void nport_post_int(int64_t port, int64_t value) {
    Dart_CObject obj;
    obj.type = Dart_CObject_kInt64;
    obj.value.as_int64 = value;
    Dart_PostCObject_DL((Dart_Port_DL)port, &obj);
}

// Post from the *calling* thread. This is the floor lane: it prices what it
// costs the main isolate to receive one message, with no sender-side hop of any
// kind in front of it.
void resqlite_nport_post_here(int64_t port, int64_t value) {
    nport_post_int(port, value);
}

// ---------------------------------------------------------------------------
// Payload handoff
//
// The rows path transfers already-built Dart objects and the bytes path sends a
// view over the reader's `json_buf`, which `SendPort.send` copies into the
// receiver (exp 174/245). A native thread can hand the same payload over as
// kExternalTypedData instead: the buffer is malloc'd, the finalizer frees it,
// and the receiving isolate never copies. This is the one place where native
// dispatch has a structural advantage over the isolate hop, so it is measured
// separately from the scalar lanes.
// ---------------------------------------------------------------------------

// Stands in for a reader connection's `json_buf`: the bytes a query has already
// serialized, which the transfer has to get to the main isolate.
static unsigned char* g_src;
static size_t g_src_len;

// Allocate the source payload once. Returns 0 on success.
int resqlite_nport_prepare_bytes(int nbytes) {
    if (nbytes < 0) return -1;
    free(g_src);
    g_src = (unsigned char*)malloc((size_t)nbytes ? (size_t)nbytes : 1);
    if (!g_src) return -1;
    memset(g_src, 'a', (size_t)nbytes);
    g_src_len = (size_t)nbytes;
    return 0;
}

static void nport_free_peer(void* isolate_data, void* peer) {
    (void)isolate_data;
    free(peer);
}

static void nport_post_copy(int64_t port, const unsigned char* src, size_t len);

static void nport_post_bytes(int64_t port, size_t len) {
    if (len > g_src_len) len = g_src_len;
    nport_post_copy(port, g_src, len);
}

static void nport_noop_finalizer(void* isolate_data, void* peer) {
    (void)isolate_data;
    (void)peer;
}

// Ceiling probe: post the source buffer itself, with no copy and a finalizer
// that frees nothing. A real implementation would have to hand `json_buf` over
// and allocate the connection a fresh one — giving up the buffer reuse exp 183
// depends on — so this is not a shippable shape. It prices the best case.
static void nport_post_borrowed(int64_t port, size_t len) {
    if (len > g_src_len) len = g_src_len;
    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = (intptr_t)len;
    obj.value.as_external_typed_data.data = g_src;
    obj.value.as_external_typed_data.peer = g_src;
    obj.value.as_external_typed_data.callback = nport_noop_finalizer;
    Dart_PostCObject_DL((Dart_Port_DL)port, &obj);
}

// Hand `len` bytes of `src` over as external typed data: one copy on this
// thread, none on the receiving isolate.
static void nport_post_copy(int64_t port, const unsigned char* src, size_t len) {
    unsigned char* copy = (unsigned char*)malloc(len ? len : 1);
    if (!copy) return;
    memcpy(copy, src, len);

    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = (intptr_t)len;
    obj.value.as_external_typed_data.data = copy;
    obj.value.as_external_typed_data.peer = copy;
    obj.value.as_external_typed_data.callback = nport_free_peer;
    Dart_PostCObject_DL((Dart_Port_DL)port, &obj);
}

// ---------------------------------------------------------------------------
// Worker thread pool
// ---------------------------------------------------------------------------

#define NPORT_QUEUE_CAP 4096
#define NPORT_MAX_THREADS 8

#define NPORT_JOB_ECHO 0
#define NPORT_JOB_BYTES 1
#define NPORT_JOB_QUERY 2
#define NPORT_JOB_BYTES_NOCOPY 3

typedef struct {
    int64_t port;
    int64_t value;
    int kind;
    void* db;
    int reader_id;
    const char* sql;
} nport_job;

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    nport_job jobs[NPORT_QUEUE_CAP];
    int head;
    int tail;
    int count;
    int stopping;
    int thread_count;
    pthread_t threads[NPORT_MAX_THREADS];
    int started;
} nport_pool;

static nport_pool g_pool;

// Jobs visible to a worker without taking the mutex, so the spin lane below can
// see an arrival without a lock round trip.
static atomic_int g_pending;

// How many times a worker re-checks `g_pending` before parking on the condvar.
// Zero is the honest primitive: the thread sleeps and the OS wakes it. A large
// budget keeps the thread hot, which burns a core but prices the mechanism's
// floor — what native dispatch could cost if the wake were free.
static atomic_int g_spin_budget;

void resqlite_nport_set_spin(int budget) {
    atomic_store(&g_spin_budget, budget < 0 ? 0 : budget);
}

// The end-to-end probe: serialize a query to JSON on this thread — the same
// `resqlite_query_bytes` a reader isolate calls — and post the bytes back. No
// Dart isolate is involved between the caller and SQLite.
//
// Parameterless by design: the point is the transport, and both arms of the
// comparison run the same SQL. `reader_id` must not be in use by a Dart reader
// worker at the same time; the harness is sequential, so it is not.
static void nport_run_query(const nport_job* job) {
    unsigned char* buf = NULL;
    int len = 0;
    int rows = 0;
    int rc = resqlite_query_bytes(
        (resqlite_db*)job->db, job->reader_id, job->sql, NULL, 0, &buf, &len,
        &rows
    );
    if (rc != SQLITE_OK || !buf) {
        nport_post_int(job->port, -(int64_t)rc);
        return;
    }
    nport_post_copy(job->port, buf, (size_t)len);
}

static void* nport_worker(void* arg) {
    (void)arg;
    for (;;) {
        int budget = atomic_load_explicit(&g_spin_budget, memory_order_relaxed);
        for (int i = 0; i < budget; i++) {
            if (atomic_load_explicit(&g_pending, memory_order_acquire) > 0) break;
#if defined(__aarch64__)
            __asm__ __volatile__("yield");
#elif defined(__x86_64__)
            __asm__ __volatile__("pause");
#endif
        }
        pthread_mutex_lock(&g_pool.mutex);
        while (g_pool.count == 0 && !g_pool.stopping) {
            pthread_cond_wait(&g_pool.cond, &g_pool.mutex);
        }
        if (g_pool.count == 0 && g_pool.stopping) {
            pthread_mutex_unlock(&g_pool.mutex);
            return NULL;
        }
        nport_job job = g_pool.jobs[g_pool.head];
        g_pool.head = (g_pool.head + 1) % NPORT_QUEUE_CAP;
        g_pool.count--;
        atomic_fetch_sub_explicit(&g_pending, 1, memory_order_release);
        pthread_mutex_unlock(&g_pool.mutex);

        if (job.kind == NPORT_JOB_QUERY) {
            nport_run_query(&job);
        } else if (job.kind == NPORT_JOB_BYTES) {
            nport_post_bytes(job.port, (size_t)job.value);
        } else if (job.kind == NPORT_JOB_BYTES_NOCOPY) {
            nport_post_borrowed(job.port, (size_t)job.value);
        } else {
            nport_post_int(job.port, job.value);
        }
    }
}

// Start `count` worker threads. Idempotent; returns the number running, or -1
// on failure.
int resqlite_nport_start(int count) {
    if (g_pool.started) return g_pool.thread_count;
    if (count < 1) count = 1;
    if (count > NPORT_MAX_THREADS) count = NPORT_MAX_THREADS;

    if (pthread_mutex_init(&g_pool.mutex, NULL) != 0) return -1;
    if (pthread_cond_init(&g_pool.cond, NULL) != 0) return -1;
    g_pool.head = g_pool.tail = g_pool.count = 0;
    g_pool.stopping = 0;
    atomic_store(&g_pending, 0);
    g_pool.thread_count = 0;
    for (int i = 0; i < count; i++) {
        if (pthread_create(&g_pool.threads[i], NULL, nport_worker, NULL) != 0) {
            break;
        }
        g_pool.thread_count++;
    }
    if (g_pool.thread_count == 0) return -1;
    g_pool.started = 1;
    return g_pool.thread_count;
}

void resqlite_nport_stop(void) {
    if (!g_pool.started) return;
    pthread_mutex_lock(&g_pool.mutex);
    g_pool.stopping = 1;
    pthread_cond_broadcast(&g_pool.cond);
    pthread_mutex_unlock(&g_pool.mutex);
    for (int i = 0; i < g_pool.thread_count; i++) {
        pthread_join(g_pool.threads[i], NULL);
    }
    pthread_mutex_destroy(&g_pool.mutex);
    pthread_cond_destroy(&g_pool.cond);
    g_pool.started = 0;
    g_pool.thread_count = 0;
}

// Hand one job to a worker thread, which posts `value` back to `port`. This is
// the dispatch lane: an FFI enqueue in place of `SendPort.send`, and a native
// post in place of the worker isolate's reply.
static int nport_enqueue(int64_t port, int64_t value, int kind) {
    pthread_mutex_lock(&g_pool.mutex);
    if (g_pool.count == NPORT_QUEUE_CAP) {
        pthread_mutex_unlock(&g_pool.mutex);
        return -1;
    }
    g_pool.jobs[g_pool.tail].port = port;
    g_pool.jobs[g_pool.tail].value = value;
    g_pool.jobs[g_pool.tail].kind = kind;
    g_pool.tail = (g_pool.tail + 1) % NPORT_QUEUE_CAP;
    g_pool.count++;
    atomic_fetch_add_explicit(&g_pending, 1, memory_order_release);
    pthread_cond_signal(&g_pool.cond);
    pthread_mutex_unlock(&g_pool.mutex);
    return 0;
}

int resqlite_nport_echo(int64_t port, int64_t value) {
    return nport_enqueue(port, value, NPORT_JOB_ECHO);
}

// Hand `nbytes` of the prepared payload to a worker thread, which copies it into
// a fresh allocation and posts it as external typed data — one copy, same as the
// `SendPort` path, but with no isolate hop and no copy on the receiving side.
int resqlite_nport_bytes(int64_t port, int nbytes) {
    return nport_enqueue(port, (int64_t)nbytes, NPORT_JOB_BYTES);
}

int resqlite_nport_bytes_nocopy(int64_t port, int nbytes) {
    return nport_enqueue(port, (int64_t)nbytes, NPORT_JOB_BYTES_NOCOPY);
}

// End-to-end probe: run `sql` on `reader_id` from a worker thread and post the
// serialized bytes to `port`. `sql` must outlive the call.
int resqlite_nport_query(int64_t port, void* db, int reader_id, const char* sql) {
    pthread_mutex_lock(&g_pool.mutex);
    if (g_pool.count == NPORT_QUEUE_CAP) {
        pthread_mutex_unlock(&g_pool.mutex);
        return -1;
    }
    nport_job* slot = &g_pool.jobs[g_pool.tail];
    slot->port = port;
    slot->value = 0;
    slot->kind = NPORT_JOB_QUERY;
    slot->db = db;
    slot->reader_id = reader_id;
    slot->sql = sql;
    g_pool.tail = (g_pool.tail + 1) % NPORT_QUEUE_CAP;
    g_pool.count++;
    atomic_fetch_add_explicit(&g_pending, 1, memory_order_release);
    pthread_cond_signal(&g_pool.cond);
    pthread_mutex_unlock(&g_pool.mutex);
    return 0;
}

#endif  // RESQLITE_NPORT
