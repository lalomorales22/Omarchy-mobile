/*
 * omarchy-rotate-keys: run omarchy-rotate when CTRL+SHIFT+F12 (the key bar's
 * ROTATE button) is pressed.
 *
 * QEMU grabs the keyboard whenever its window has focus, so window-manager
 * key bindings never fire. XInput2 raw key events reach root-window listeners
 * regardless of grabs. Built on the phone by scripts/install-launcher.sh:
 *   clang -O2 -o omarchy-rotate-keys rotate-keys.c -lX11 -lXi
 */
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <X11/keysym.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "omarchy-rotate-keys: cannot open display\n");
        return 1;
    }

    int xi_opcode, event, error, major = 2, minor = 2;
    if (!XQueryExtension(display, "XInputExtension", &xi_opcode, &event, &error) ||
        XIQueryVersion(display, &major, &minor) != Success) {
        fprintf(stderr, "omarchy-rotate-keys: X server lacks XInput 2.2\n");
        return 1;
    }

    unsigned char bits[XIMaskLen(XI_LASTEVENT)] = {0};
    XISetMask(bits, XI_RawKeyPress);
    XISetMask(bits, XI_RawKeyRelease);
    XIEventMask mask = {XIAllMasterDevices, sizeof bits, bits};
    XISelectEvents(display, DefaultRootWindow(display), &mask, 1);
    XFlush(display);

    KeyCode f12 = XKeysymToKeycode(display, XK_F12);
    KeyCode ctrl_l = XKeysymToKeycode(display, XK_Control_L), ctrl_r = XKeysymToKeycode(display, XK_Control_R);
    KeyCode shift_l = XKeysymToKeycode(display, XK_Shift_L), shift_r = XKeysymToKeycode(display, XK_Shift_R);
    int ctrl = 0, shift = 0;

    signal(SIGCHLD, SIG_IGN);
    for (;;) {
        XEvent e;
        XNextEvent(display, &e);
        if (e.xcookie.type != GenericEvent || e.xcookie.extension != xi_opcode ||
            !XGetEventData(display, &e.xcookie))
            continue;

        XIRawEvent *raw = e.xcookie.data;
        int down = e.xcookie.evtype == XI_RawKeyPress;
        if (raw->detail == ctrl_l || raw->detail == ctrl_r)
            ctrl = down;
        else if (raw->detail == shift_l || raw->detail == shift_r)
            shift = down;
        else if (down && raw->detail == f12 && ctrl && shift && fork() == 0) {
            execlp("omarchy-rotate", "omarchy-rotate", (char *)NULL);
            _exit(127);
        }
        XFreeEventData(display, &e.xcookie);
    }
}
