#include <stdio.h>
#include <stdlib.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

static void require(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message);
        exit(1);
    }
}

int main(void) {
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    require(context != NULL, "Could not create isolated XKB context");
    struct xkb_rule_names names = {
        .model = getenv("XKB_DEFAULT_MODEL"),
        .layout = getenv("GREETER_LAYOUT"),
        .variant = getenv("GREETER_VARIANT"),
        .options = getenv("GREETER_OPTIONS"),
    };
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    require(keymap != NULL, "Configured greeter layout did not compile");
    struct xkb_state *state = xkb_state_new(keymap);
    require(state != NULL, "Could not create isolated XKB state");
    xkb_keycode_t a = xkb_keymap_key_by_name(keymap, "AC01");
    xkb_keycode_t o = xkb_keymap_key_by_name(keymap, "AD09");
    xkb_keycode_t u = xkb_keymap_key_by_name(keymap, "AD07");
    xkb_keycode_t alt = xkb_keymap_key_by_name(keymap, "RALT");
    require(a != XKB_KEYCODE_INVALID && alt != XKB_KEYCODE_INVALID, "Missing configured keys");
    require(xkb_state_key_get_one_sym(state, a) == XKB_KEY_a, "Default A key changed");
    xkb_state_update_key(state, alt, XKB_KEY_DOWN);
    require(xkb_state_key_get_one_sym(state, a) == XKB_KEY_adiaeresis, "Right Alt+A must produce umlaut A");
    require(xkb_state_key_get_one_sym(state, o) == XKB_KEY_odiaeresis, "Right Alt+O must produce umlaut O");
    require(xkb_state_key_get_one_sym(state, u) == XKB_KEY_udiaeresis, "Right Alt+U must produce umlaut U");
    xkb_state_update_key(state, alt, XKB_KEY_UP);
    require(xkb_state_key_get_one_sym(state, a) == XKB_KEY_a, "Releasing Alt did not restore A");
    xkb_state_unref(state);
    xkb_keymap_unref(keymap);
    xkb_context_unref(context);
    puts("Greeter custom keymap passed; no device/compositor connection used");
    return 0;
}
