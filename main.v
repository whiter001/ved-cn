module main

import app
import os

fn main() {
	app.run(os.args[1..]) or {
		eprintln(err.msg())
		exit(1)
	}
}