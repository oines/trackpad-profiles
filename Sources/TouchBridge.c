#include "TouchBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>

// Contact layout and device family checks are derived from Mac-trackpad-mapper
// (MIT, Austin Siu). Its header credits TouchSynthesis, Calf Trail Software.
typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;
    float size;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int32_t reserved[2];
    float density;
} MTContact;

typedef CFTypeRef MTDevice;
typedef int (*MTFrameCallback)(MTDevice, MTContact *, int, double, int, void *);

static struct {
    void *library;
    CFArrayRef (*createList)(void);
    int32_t (*getFamilyID)(MTDevice, int *);
    void (*registerContact)(MTDevice, MTFrameCallback, void *);
    void (*unregisterContact)(MTDevice, MTFrameCallback);
    int32_t (*start)(MTDevice, int);
    int32_t (*stop)(MTDevice);
} api;

// Device ownership is confined to the main thread. Contact state is serialized
// across callbacks and cleared before stopping any device.
static CFMutableArrayRef listeningDevices;
static pthread_mutex_t contactLock = PTHREAD_MUTEX_INITIALIZER;
static uintptr_t generation;
static TPContactCallback clientCallback;
static void *clientContext;
static MTDevice activeDevice;
static int32_t activePath;
static bool tracking;

static bool loadAPI(void) {
    if (api.library) {
        return true;
    }

    api.library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                        RTLD_NOW | RTLD_LOCAL);
    if (!api.library) {
        return false;
    }

    api.createList = dlsym(api.library, "MTDeviceCreateList");
    api.getFamilyID = dlsym(api.library, "MTDeviceGetFamilyID");
    api.registerContact = dlsym(api.library, "MTRegisterContactFrameCallbackWithRefcon");
    api.unregisterContact = dlsym(api.library, "MTUnregisterContactFrameCallback");
    api.start = dlsym(api.library, "MTDeviceStart");
    api.stop = dlsym(api.library, "MTDeviceStop");
    if (!api.createList || !api.getFamilyID || !api.registerContact || !api.unregisterContact ||
        !api.start || !api.stop) {
        dlclose(api.library);
        api.library = NULL;
        return false;
    }

    // Keep the loaded image available while its private worker threads exist.
    return true;
}

static bool isTrackpad(MTDevice device) {
    int family = 0;
    if (api.getFamilyID(device, &family) != 0) {
        return false;
    }
    return family >= 98 && family != 112 && family != 113;
}

static void reportContact(MTDevice device, const MTContact *contacts, int count) {
    if (activeDevice && activeDevice != device) {
        return;
    }

    bool hasContact = false;
    const MTContact *primary = NULL;
    for (int i = 0; contacts && i < count; i++) {
        const MTContact *touch = &contacts[i];
        if (touch->state != 3 && touch->state != 4) {
            continue;
        }
        hasContact = true;
        if (activeDevice && (!tracking || touch->pathIndex != activePath)) {
            continue;
        }
        if (!primary) {
            primary = touch;
        }
    }

    if (primary) {
        activeDevice = device;
        activePath = primary->pathIndex;
        tracking = true;
        double x = primary->normalized.position.x;
        double y = 1.0 - primary->normalized.position.y;
        if (isfinite(x) && isfinite(y)) {
            clientCallback(fmin(1.0, fmax(0.0, x)), fmin(1.0, fmax(0.0, y)), true, clientContext);
        }
        return;
    }

    if (tracking) {
        tracking = false;
        clientCallback(0.0, 0.0, false, clientContext);
    }
    // Secondary fingers should never cause the cursor to jump after the
    // original finger leaves. Wait until this trackpad is clear to start again.
    if (!hasContact) {
        activeDevice = NULL;
    }
}

static int contactFrame(MTDevice device, MTContact *contacts, int count, double timestamp,
                        int frame, void *frameGeneration) {
    (void)timestamp;
    (void)frame;

    pthread_mutex_lock(&contactLock);
    if (clientCallback && generation == (uintptr_t)frameGeneration) {
        reportContact(device, contacts, count);
    }
    pthread_mutex_unlock(&contactLock);
    return 0;
}

int TPStart(TPContactCallback callback, void *context) {
    if (!callback || !loadAPI()) {
        return -1;
    }
    if (listeningDevices) {
        return (int)CFArrayGetCount(listeningDevices);
    }

    CFArrayRef devices = api.createList();
    if (!devices) {
        return -1;
    }
    CFMutableArrayRef started = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (!started) {
        CFRelease(devices);
        return -1;
    }

    pthread_mutex_lock(&contactLock);
    ++generation;
    void *frameGeneration = (void *)generation;
    pthread_mutex_unlock(&contactLock);

    bool foundTrackpad = false;
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        MTDevice device = CFArrayGetValueAtIndex(devices, i);
        if (!isTrackpad(device)) {
            continue;
        }
        foundTrackpad = true;
        api.registerContact(device, contactFrame, frameGeneration);
        if (api.start(device, 0) == 0) {
            CFArrayAppendValue(started, device);
        } else {
            api.unregisterContact(device, contactFrame);
        }
    }
    CFRelease(devices);

    int count = (int)CFArrayGetCount(started);
    if (count == 0) {
        CFRelease(started);
        return foundTrackpad ? -1 : 0;
    }

    listeningDevices = started;
    pthread_mutex_lock(&contactLock);
    clientContext = context;
    clientCallback = callback;
    pthread_mutex_unlock(&contactLock);
    return count;
}

void TPStop(void) {
    if (!listeningDevices) {
        return;
    }

    pthread_mutex_lock(&contactLock);
    clientCallback = NULL;
    clientContext = NULL;
    activeDevice = NULL;
    tracking = false;
    pthread_mutex_unlock(&contactLock);

    for (CFIndex i = 0; i < CFArrayGetCount(listeningDevices); i++) {
        MTDevice device = CFArrayGetValueAtIndex(listeningDevices, i);
        api.unregisterContact(device, contactFrame);
        api.stop(device);
    }
    CFRelease(listeningDevices);
    listeningDevices = NULL;
}
