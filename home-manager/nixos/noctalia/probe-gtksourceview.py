"""Headless style-manager probe; one GTK major per process, no application init."""

import ctypes as c
import json
import sys


library, directory = sys.argv[1:]
lib = c.CDLL(library)
lib.gtk_source_style_scheme_manager_new.restype = c.c_void_p
manager = lib.gtk_source_style_scheme_manager_new()
lib.gtk_source_style_scheme_manager_set_search_path.argtypes = [c.c_void_p, c.POINTER(c.c_char_p)]
paths = (c.c_char_p * 2)(directory.encode(), None)
lib.gtk_source_style_scheme_manager_set_search_path(manager, paths)
lib.gtk_source_style_scheme_manager_force_rescan.argtypes = [c.c_void_p]
lib.gtk_source_style_scheme_manager_force_rescan(manager)
lib.gtk_source_style_scheme_manager_get_scheme.argtypes = [c.c_void_p, c.c_char_p]
lib.gtk_source_style_scheme_manager_get_scheme.restype = c.c_void_p
scheme = lib.gtk_source_style_scheme_manager_get_scheme(manager, b"stylix")
if not scheme:
    raise RuntimeError("Native GtkSourceView parser did not load the legacy scheme")
lib.gtk_source_style_scheme_get_name.argtypes = [c.c_void_p]
lib.gtk_source_style_scheme_get_name.restype = c.c_char_p
lib.gtk_source_style_scheme_get_style.argtypes = [c.c_void_p, c.c_char_p]
lib.gtk_source_style_scheme_get_style.restype = c.c_void_p
style = lib.gtk_source_style_scheme_get_style(scheme, b"text")
foreground, background = c.c_char_p(), c.c_char_p()
if style:
    lib.g_object_get.argtypes = [c.c_void_p, c.c_char_p]
    lib.g_object_get(style, b"foreground", c.byref(foreground),
                     b"background", c.byref(background), None)
print(json.dumps({"name": lib.gtk_source_style_scheme_get_name(scheme).decode(),
                  "foreground": foreground.value.decode() if foreground.value else None,
                  "background": background.value.decode() if background.value else None}))
