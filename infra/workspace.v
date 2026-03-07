module infra

import os

pub struct WorkspaceIndex {
pub:
	root  string
	files []string
}

pub fn build_workspace_index(root string) !WorkspaceIndex {
	if root == '' || !os.exists(root) || !os.is_dir(root) {
		return WorkspaceIndex{
			root: root
			files: []string{}
		}
	}
	mut files := []string{}
	collect_files(root, root, mut files)!
	files.sort()
	return WorkspaceIndex{
		root: root
		files: files
	}
}

pub fn filter_paths(paths []string, query string, limit int) []string {
	if paths.len == 0 || limit <= 0 {
		return []string{}
	}
	normalized_query := query.to_lower().trim_space()
	if normalized_query == '' {
		return paths[..min_int(paths.len, limit)]
	}
	mut direct := []string{}
	mut fuzzy := []string{}
	for path in paths {
		lower_path := path.to_lower()
		if lower_path.contains(normalized_query) {
			direct << path
			continue
		}
		if is_subsequence(normalized_query, lower_path) {
			fuzzy << path
		}
	}
	mut result := []string{}
	for item in direct {
		result << item
		if result.len >= limit {
			return result
		}
	}
	for item in fuzzy {
		result << item
		if result.len >= limit {
			return result
		}
	}
	return result
}

fn collect_files(root string, current string, mut files []string) ! {
	entries := os.ls(current)!
	for entry in entries {
		if should_skip(entry) {
			continue
		}
		path := os.join_path(current, entry)
		if os.is_dir(path) {
			collect_files(root, path, mut files)!
			continue
		}
		rel := path[root.len + 1..]
		files << rel
	}
}

fn should_skip(name string) bool {
	if name in ['.git', '.idea', '.vscode', 'node_modules', 'target', 'dist', 'build', 'out'] {
		return true
	}
	return name.starts_with('.')
}

fn is_subsequence(query string, value string) bool {
	if query.len == 0 {
		return true
	}
	mut q := 0
	for ch in value {
		if ch == query[q] {
			q++
			if q == query.len {
				return true
			}
		}
	}
	return false
}

fn min_int(left int, right int) int {
	if left < right {
		return left
	}
	return right
}