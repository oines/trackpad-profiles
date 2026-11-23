#ifndef TRACKPAD_TOUCH_BRIDGE_H
#define TRACKPAD_TOUCH_BRIDGE_H

#include <stdbool.h>

typedef void (*TPContactCallback)(double x, double y, bool touching, void *context);

// Call start and stop on the main thread. Start returns the number of listening
// trackpads, zero when none are connected, or a negative value on failure.
// Contact callbacks arrive on a private thread and are serialized. Coordinates
// are normalized from the top left and only meaningful while touching is true.
// Callbacks must return promptly without calling start/stop or waiting on the
// main thread. The context must remain valid until TPStop returns.
int TPStart(TPContactCallback callback, void *context);
void TPStop(void);

#endif
