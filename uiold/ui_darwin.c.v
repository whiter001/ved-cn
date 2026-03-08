module uiold

import os

#flag -framework Carbon
#flag -framework Cocoa

#include <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>

#include "@VROOT/uiold/uiold.m"

fn C.reg_key_ved2()
fn C.setup_mac_app()
fn C.set_ime_position(int, int, int)
fn C.focus_native_input(bool)
fn C.reg_ved_insert_cb(voidptr)
fn C.reg_ved_marked_cb(voidptr)
fn C.reg_ved_instance(voidptr)

pub fn reg_key_ved() {
	C.reg_key_ved2()
}

pub fn setup_mac_app() {
	C.setup_mac_app()
}

pub fn set_ime_position(x int, y int, h int, scale f32) {
	C.set_ime_position(x, y, h)
}

pub fn focus_native_input(focus bool) {
	if os.getenv('VED_TEST') != '' {
		return
	}
	C.focus_native_input(focus)
}

pub fn reg_ved_insert_cb(cb voidptr) {
	C.reg_ved_insert_cb(cb)
}

pub fn reg_ved_marked_cb(cb voidptr) {
	C.reg_ved_marked_cb(cb)
}

pub fn reg_ved_instance(ved voidptr) {
	C.reg_ved_instance(ved)
}