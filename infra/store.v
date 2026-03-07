module infra

import os

pub struct FileStore {}

pub fn new_file_store() FileStore {
	return FileStore{}
}

pub fn (store FileStore) exists(path string) bool {
	return path != '' && os.exists(path)
}

pub fn (store FileStore) is_dir(path string) bool {
	return path != '' && os.is_dir(path)
}

pub fn (store FileStore) load(path string) !string {
	return os.read_file(path)
}

pub fn (store FileStore) save(path string, text string) ! {
	dir := os.dir(path)
	if dir != '' && !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	os.write_file(path, text)!
}