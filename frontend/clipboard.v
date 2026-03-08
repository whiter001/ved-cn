module frontend

import os
import rand

fn write_system_clipboard(text string) ! {
	$if macos {
		temp_path := os.join_path(os.temp_dir(), 'ved-cn-clipboard-${rand.u32()}.txt')
		defer {
			os.rm(temp_path) or {}
		}
		os.write_file(temp_path, text)!
		result := os.execute("pbcopy < '${temp_path}'")
		if result.exit_code != 0 {
			return error(result.output)
		}
		return
	}
	return error('当前平台暂未实现系统剪贴板写入')
}
