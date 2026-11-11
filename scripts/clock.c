// Stops the wall clock in iikb's app and keyboard at IIKB_NOW (seconds since 1970), so a screen that shows a date or an
// age ("48m", Today, a week's chart) draws the same in every run (scripts/screens.py). Loaded into the simulator's
// processes through DYLD_INSERT_LIBRARIES (scripts/sim boot), it stops time only in executables inside iikb.app, and
// there not for the security and networking libraries, whose certificate checks need the real date (a stopped one
// before a server's certificate was issued fails every request). Monotonic clocks (animations, timers, touches) run on.

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>

#define INTERPOSE(replacement, original)                                                                     \
  __attribute__((used)) static const struct {                                                             \
    const void *replacement, *original;                                                                     \
  } interpose_##original __attribute__((section("__DATA,__interpose"))) = {(const void *)replacement, \
                                                                            (const void *)original};

static int state = -1;
static struct timespec now;

static int stopped(const void *caller) {
  if (state < 0) {
    char path[PATH_MAX];
    uint32_t size = sizeof path;
    const char *at = getenv("IIKB_NOW");
    state = at && _NSGetExecutablePath(path, &size) == 0 && strstr(path, "/iikb.app/") != NULL;
    if (state) {
      double seconds = atof(at);
      now.tv_sec = (time_t)seconds;
      now.tv_nsec = (long)((seconds - (double)now.tv_sec) * 1e9);
    }
  }
  if (!state) return 0;
  static const char *const real[] = {"/Security.framework/", "/CFNetwork.framework/", "/Network.framework/",
                                     "libboringssl", "libcoretls", "libnetwork"};
  Dl_info image;
  if (!caller || !dladdr(caller, &image) || !image.dli_fname) return 1;
  for (size_t i = 0; i < sizeof real / sizeof *real; i++)
    if (strstr(image.dli_fname, real[i])) return 0;
  return 1;
}

#define CALLER __builtin_return_address(0)

static int stopped_clock_gettime(clockid_t clock, struct timespec *out) {
  if (clock != CLOCK_REALTIME || !stopped(CALLER)) return clock_gettime(clock, out);
  *out = now;
  return 0;
}

static uint64_t stopped_clock_gettime_nsec_np(clockid_t clock) {
  if (clock != CLOCK_REALTIME || !stopped(CALLER)) return clock_gettime_nsec_np(clock);
  return (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
}

static int stopped_gettimeofday(struct timeval *out, void *zone) {
  if (!stopped(CALLER)) return gettimeofday(out, zone);
  if (out) *out = (struct timeval){.tv_sec = now.tv_sec, .tv_usec = (suseconds_t)(now.tv_nsec / 1000)};
  return 0;
}

static time_t stopped_time(time_t *out) {
  if (!stopped(CALLER)) return time(out);
  if (out) *out = now.tv_sec;
  return now.tv_sec;
}

// WHY: the real CFAbsoluteTimeGetCurrent reads the clock from inside CoreFoundation, which would come back stopped.
static CFAbsoluteTime stopped_CFAbsoluteTimeGetCurrent(void) {
  struct timespec at = now;
  if (!stopped(CALLER)) clock_gettime(CLOCK_REALTIME, &at);
  return (double)at.tv_sec + (double)at.tv_nsec / 1e9 - kCFAbsoluteTimeIntervalSince1970;
}

INTERPOSE(stopped_clock_gettime, clock_gettime)
INTERPOSE(stopped_clock_gettime_nsec_np, clock_gettime_nsec_np)
INTERPOSE(stopped_gettimeofday, gettimeofday)
INTERPOSE(stopped_time, time)
INTERPOSE(stopped_CFAbsoluteTimeGetCurrent, CFAbsoluteTimeGetCurrent)
