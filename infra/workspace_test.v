module infra

fn test_filter_paths_prefers_direct_matches() {
	paths := ['src/main.v', 'src/editor/state.v', 'docs/architecture.md', 'frontend/app.v']
	result := filter_paths(paths, 'app', 10)
	assert result.len >= 1
	assert result[0] == 'frontend/app.v'
}

fn test_filter_paths_supports_subsequence() {
	paths := ['frontend/app.v', 'editor/session.v', 'infra/workspace.v']
	result := filter_paths(paths, 'fap', 10)
	assert result.len >= 1
	assert 'frontend/app.v' in result
}