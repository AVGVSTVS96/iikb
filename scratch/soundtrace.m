#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreHaptics/CoreHaptics.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <mach-o/dyld.h>
#include <os/log.h>
#include <fcntl.h>
#include <sys/time.h>
#include <unistd.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>

typedef struct { const void *replacement; const void *replacee; } interpose_t;
#define INTERPOSE(r, o) __attribute__((used)) static const interpose_t _interpose_##o \
  __attribute__((section("__DATA,__interpose"))) = { (const void *)r, (const void *)o };

extern void AudioServicesPlaySystemSoundWithOptions(SystemSoundID, CFDictionaryRef, void (^)(void)) __attribute__((weak_import));
extern void AudioServicesPlaySystemSoundWithVibration(SystemSoundID, id, NSDictionary *) __attribute__((weak_import));

static os_log_t logger(void) {
  static os_log_t l; static dispatch_once_t once;
  dispatch_once(&once, ^{ l = os_log_create("sndtrace", "trace"); });
  return l;
}

static void filelog(NSString *line);

static void report(const char *fn, SystemSoundID sid, CFTypeRef extra) {
  void *frames[14];
  int n = backtrace(frames, 14);
  NSMutableString *bt = [NSMutableString string];
  for (int i = 1; i < n; i++) {
    Dl_info info;
    if (dladdr(frames[i], &info) && info.dli_sname) {
      const char *image = info.dli_fname ? strrchr(info.dli_fname, '/') : NULL;
      [bt appendFormat:@" | %s:%s", image ? image + 1 : "?", info.dli_sname];
    } else [bt appendFormat:@" | %p", frames[i]];
  }
  NSString *desc = extra ? [(__bridge id)extra description] : @"";
  desc = [[desc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
  os_log_error(logger(), "SNDTRACE %{public}s fn=%{public}s id=%u extra=%{public}@ bt=%{public}@",
               getprogname(), fn, (unsigned)sid, desc, bt);
  filelog([NSString stringWithFormat:@"fn=%s id=%u extra=%@ bt=%@", fn, (unsigned)sid, desc, bt]);
}

static void timed(const char *fn, SystemSoundID s, void (^c)(void), void (^play)(void (^)(void))) {
  report(fn, s, NULL);
  struct timeval a; gettimeofday(&a, NULL);
  play(^{
    struct timeval b; gettimeofday(&b, NULL);
    filelog([NSString stringWithFormat:@"done fn=%s id=%u after_ms=%.1f", fn, (unsigned)s, (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_usec - a.tv_usec) / 1e3]);
    if (c) c();
  });
}
static void my_play(SystemSoundID s) { timed("AudioServicesPlaySystemSound", s, nil, ^(void (^d)(void)) { AudioServicesPlaySystemSoundWithCompletion(s, d); }); }
static void my_alert(SystemSoundID s) { report("AudioServicesPlayAlertSound", s, NULL); AudioServicesPlayAlertSound(s); }
static void my_play_c(SystemSoundID s, void (^c)(void)) { report("AudioServicesPlaySystemSoundWithCompletion", s, NULL); AudioServicesPlaySystemSoundWithCompletion(s, c); }
static void my_alert_c(SystemSoundID s, void (^c)(void)) { report("AudioServicesPlayAlertSoundWithCompletion", s, NULL); AudioServicesPlayAlertSoundWithCompletion(s, c); }
static void my_play_o(SystemSoundID s, CFDictionaryRef o, void (^c)(void)) { timed("WithOptions", s, c, ^(void (^d)(void)) { AudioServicesPlaySystemSoundWithOptions(s, o, d); }); }
static void my_play_v(SystemSoundID s, id x, NSDictionary *d) { report("AudioServicesPlaySystemSoundWithVibration", s, (__bridge CFTypeRef)d); AudioServicesPlaySystemSoundWithVibration(s, x, d); }
static OSStatus my_create(CFURLRef url, SystemSoundID *out) {
  OSStatus r = AudioServicesCreateSystemSoundID(url, out);
  report("AudioServicesCreateSystemSoundID", out ? *out : 0, url);
  return r;
}

INTERPOSE(my_play, AudioServicesPlaySystemSound)
INTERPOSE(my_alert, AudioServicesPlayAlertSound)
INTERPOSE(my_play_c, AudioServicesPlaySystemSoundWithCompletion)
INTERPOSE(my_alert_c, AudioServicesPlayAlertSoundWithCompletion)
INTERPOSE(my_play_o, AudioServicesPlaySystemSoundWithOptions)
INTERPOSE(my_play_v, AudioServicesPlaySystemSoundWithVibration)
INTERPOSE(my_create, AudioServicesCreateSystemSoundID)


static void filelog(NSString *line) {
  static int fd = -2;
  if (fd == -2) fd = open("/tmp/sndtrace.log", O_WRONLY | O_APPEND | O_CREAT, 0666);
  if (fd < 0) return;
  struct timeval tv; gettimeofday(&tv, NULL);
  NSString *full = [NSString stringWithFormat:@"%ld.%06d %s[%d] %@\n", tv.tv_sec, tv.tv_usec, getprogname(), getpid(), line];
  NSData *d = [full dataUsingEncoding:NSUTF8StringEncoding];
  write(fd, d.bytes, d.length);
}
#define LOG(fmt, ...) do { os_log_error(logger(), "SNDTRACE %{public}s " fmt, getprogname(), ##__VA_ARGS__); \
  filelog([NSString stringWithFormat:[[@fmt stringByReplacingOccurrencesOfString:@"%{public}" withString:@"%"] stringByReplacingOccurrencesOfString:@"%s" withString:@"%s"], ##__VA_ARGS__]); } while (0)

static NSString *keyName(id key) {
  if (!key) return @"nil";
  id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
  id name = [key respondsToSelector:NSSelectorFromString(@"name")] ? send(key, NSSelectorFromString(@"name")) : @"?";
  id rep = [key respondsToSelector:NSSelectorFromString(@"representedString")] ? send(key, NSSelectorFromString(@"representedString")) : @"?";
  long long type = [key respondsToSelector:NSSelectorFromString(@"interactionType")] ? ((long long (*)(id, SEL))objc_msgSend)(key, NSSelectorFromString(@"interactionType")) : -1;
  return [NSString stringWithFormat:@"%@ rep=%@ interactionType=%lld", name, rep, type];
}

static Method method(const char *cls, const char *sel, BOOL meta) {
  Class c = objc_getClass(cls);
  if (meta && c) c = object_getClass(c);
  Method m = c ? class_getInstanceMethod(c, sel_registerName(sel)) : NULL;
  if (!m) LOG("nohook %{public}s %{public}s", cls, sel);
  return m;
}

#define SWAP(cls, sel, meta, ret, args, call, body) do { \
  Method m = method(cls, sel, meta); if (!m) break; \
  ret (*old) args = (ret (*) args)method_getImplementation(m); SEL s = sel_registerName(sel); (void)s; \
  method_setImplementation(m, imp_implementationWithBlock(body)); } while (0)

static NSMutableSet *hookedPlayers;

static void hookPlayerClass(Class c) {
  if (!c || [hookedPlayers containsObject:c]) return;
  [hookedPlayers addObject:c];
  Method m = class_getInstanceMethod(c, @selector(startAtTime:error:));
  if (!m) { LOG("player class %{public}s has no startAtTime:error:", class_getName(c)); return; }
  BOOL (*old)(id, SEL, double, NSError **) = (BOOL (*)(id, SEL, double, NSError **))method_getImplementation(m);
  method_setImplementation(m, imp_implementationWithBlock(^BOOL(id self, double t, NSError **e) {
    LOG("player start %{public}s %p", class_getName(object_getClass(self)), self);
    return old(self, @selector(startAtTime:error:), t, e);
  }));
}

static void hooks(void) {
  hookedPlayers = [NSMutableSet set];
  SWAP("_UIKBFeedbackGenerator", "actionOccurred:", NO, void, (id, SEL, long long), , ^(id self, long long a) {
    LOG("objc=-[_UIKBFeedbackGenerator actionOccurred:] action=%lld", a); old(self, s, a); });
  SWAP("_UIKBFeedbackGenerator", "actionOccurred:atLocation:", NO, void, (id, SEL, long long, CGPoint), , ^(id self, long long a, CGPoint p) {
    LOG("objc=-[_UIKBFeedbackGenerator actionOccurred:atLocation:] action=%lld x=%.0f", a, p.x); old(self, s, a, p); });
  SWAP("_UIKBFeedbackGenerator", "actionOccurred:textLength:atLocation:", NO, void, (id, SEL, long long, long long, CGPoint), , ^(id self, long long a, long long l, CGPoint p) {
    LOG("objc=-[_UIKBFeedbackGenerator actionOccurred:textLength:atLocation:] action=%lld len=%lld x=%.0f", a, l, p.x); old(self, s, a, l, p); });
  SWAP("_UIKBFeedbackGenerator", "_updateMode", NO, long long, (id, SEL), , ^long long(id self) {
    long long r = old(self, s); LOG("objc=-[_UIKBFeedbackGenerator _updateMode] -> %lld", r); return r; });
  SWAP("_UIKBFeedbackGenerator", "_areKeyClicksEnabled", NO, BOOL, (id, SEL), , ^BOOL(id self) {
    BOOL r = old(self, s); LOG("objc=-[_UIKBFeedbackGenerator _areKeyClicksEnabled] -> %d", r); return r; });
  SWAP("_UIKBFeedbackGenerator", "_isRingerSwitchOn", NO, BOOL, (id, SEL), , ^BOOL(id self) {
    BOOL r = old(self, s); LOG("objc=-[_UIKBFeedbackGenerator _isRingerSwitchOn] -> %d", r); return r; });
  const char *sels[] = {"playKeyClickSoundForKey:", "playKeyClickSoundOnDownForKey:", "playKeyClickSoundOnUpForKey:", "playKeyReleaseSoundForKey:"};
  for (int i = 0; i < 4; i++) {
    const char *sel = sels[i];
    NSString *name = @(sel);
    SWAP("UIKeyboardLayoutStar", sel, NO, void, (id, SEL, id), , ^(id self, id key) {
      LOG("objc=-[UIKeyboardLayoutStar %{public}@] key=%{public}@", name, keyName(key)); old(self, s, key); });
  }
  SWAP("UIKeyboardImpl", "playDeleteKeyFeedbackRepeat:rapid:deleteCount:", NO, void, (id, SEL, BOOL, BOOL, long long), , ^(id self, BOOL r, BOOL q, long long n) {
    LOG("objc=-[UIKeyboardImpl playDeleteKeyFeedbackRepeat:%d rapid:%d deleteCount:%lld]", r, q, n); old(self, s, r, q, n); });
  SWAP("UIKeyboardImpl", "playInputClick", NO, BOOL, (id, SEL), , ^BOOL(id self) {
    BOOL r = old(self, s); LOG("objc=-[UIKeyboardImpl playInputClick] -> %d", r); return r; });
  SWAP("UIDevice", "playInputClick", NO, void, (id, SEL), , ^(id self) {
    LOG("objc=-[UIDevice playInputClick]"); old(self, s); });
  SWAP("UIDevice", "_playSystemSound:", NO, void, (id, SEL, unsigned), , ^(id self, unsigned i) {
    LOG("objc=-[UIDevice _playSystemSound:%u] enabled=%d", i, ((BOOL (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"_isSystemSoundEnabled"))); old(self, s, i); });
  SWAP("UIPeripheralHost", "keyClicksEnabled", NO, BOOL, (id, SEL), , ^BOOL(id self) {
    BOOL r = old(self, s); LOG("objc=-[UIPeripheralHost keyClicksEnabled] -> %d", r); return r; });
  SWAP("CHHapticPattern", "patternForKey:error:", YES, id, (id, SEL, id, NSError **), , ^id(id self, id key, NSError **e) {
    NSError *err = nil;
    id r = old(self, s, key, &err);
    if (e) *e = err;
    NSString *d = r ? [[(CHHapticPattern *)r exportDictionaryAndReturnError:nil] description] : @"nil";
    d = [[d componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    LOG("objc=+[CHHapticPattern patternForKey:%{public}@] err=%{public}@ pattern=%{public}@", key, err, d);
    return r; });
  SWAP("CHHapticEngine", "createPlayerWithPattern:error:", NO, id, (id, SEL, id, NSError **), , ^id(id self, id pat, NSError **e) {
    id r = old(self, s, pat, e);
    LOG("objc=-[CHHapticEngine createPlayerWithPattern:] -> %{public}s %p", r ? class_getName(object_getClass(r)) : "nil", r);
    if (r) hookPlayerClass(object_getClass(r));
    return r; });
  SWAP("CHHapticEngine", "initWithAudioSession:sessionIsShared:options:error:", NO, id, (id, SEL, id, BOOL, id, NSError **), , ^id(id self, id session, BOOL shared, id options, NSError **e) {
    id r = old(self, s, session, shared, options, e);
    LOG("objc=-[CHHapticEngine initWithAudioSession:%{public}@ shared:%d options:%{public}@] -> %p", session, shared, [[options description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "], r);
    return r; });
  Boolean exists = false;
  Boolean value = CFPreferencesGetAppBooleanValue(CFSTR("keyboard-audio"), CFSTR("com.apple.preferences.sounds"), &exists);
  id ud = [[[NSUserDefaults alloc] initWithSuiteName:@"com.apple.preferences.sounds"] objectForKey:@"keyboard-audio"];
  LOG("pref keyboard-audio CFPreferences value=%d exists=%d NSUserDefaults=%{public}@", value, exists, ud);
}
static void soundFiles(void) {
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const char *name = _dyld_get_image_name(i);
    if (!strstr(name, "/AudioToolbox.framework/AudioToolbox")) continue;
    const uint8_t *fn = (const uint8_t *)_dyld_get_image_header(i) + 0x252b0;
    static const uint8_t prologue[] = {0xfc, 0x6f, 0xbc, 0xa9, 0xf6, 0x57, 0x01, 0xa9};
    if (memcmp(fn, prologue, sizeof prologue)) { LOG("soundfile prologue mismatch in %{public}s", name); return; }
    uint32_t (*get)(uint32_t, char *, uint32_t, bool *) = (void *)fn;
    for (uint32_t id = 1000; id < 1700; id++) {
      char path[1024] = {0}; bool flag = false;
      uint32_t r = get(id, path, sizeof path, &flag);
      if (path[0]) LOG("soundfile id=%u r=%u flag=%d path=%{public}s", id, r, flag, path);
    }
    return;
  }
  LOG("soundfile no AudioToolbox image");
}

__attribute__((constructor)) static void start(void) {
  const char *p = getprogname();
  if (strcmp(p, "iikb") && strcmp(p, "Keyboard") && strcmp(p, "AppUITests-Runner")) return;
  LOG("loaded");
  dispatch_async(dispatch_get_main_queue(), ^{
    dlopen("/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics", RTLD_NOW);
    hooks();
  });
}
