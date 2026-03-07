module app

import core
import frontend
import infra
import os

pub fn run(args []string) ! {
	store := infra.new_file_store()
	buffers, workspace_root := load_initial_buffers(store, args)!
	mut window := frontend.new_window(buffers, store, workspace_root)
	window.run()
}

fn load_initial_buffers(store infra.FileStore, args []string) !([]core.Buffer, string) {
	mut workspace_root := os.getwd()
	mut buffers := []core.Buffer{}
	if args.len == 0 {
		return [core.new_buffer('', '')], workspace_root
	}
	for arg in args {
		target := os.real_path(arg)
		if store.exists(target) && store.is_dir(target) {
			workspace_root = target
			continue
		}
		if store.exists(target) {
			workspace_root = os.dir(target)
			buffers << core.new_buffer(target, store.load(target)!)
			continue
		}
		workspace_root = if os.dir(target) == '' { workspace_root } else { os.dir(target) }
		buffers << core.new_buffer(target, '')
	}
	if buffers.len == 0 {
		buffers << core.new_buffer('', '')
	}
	return buffers, workspace_root
}