package http

import "core:flags"
import "core:fmt"
import "core:os"

Config :: struct {
	debug: bool `args:"name=debug"`,
}

config: Config

init_debug :: proc() -> bool {
	err := flags.parse(&config, os.args[1:], .Unix)

	if err != nil {
		fmt.eprintfln("Invalid arguments: %v", err)
		return false
	}

	if config.debug {
		fmt.println("DEBUG MODE ON")
	}

	return true
}

debugf :: proc(format: string, args: ..any) {
	if !config.debug {
		return
	}

	fmt.printf(format, ..args)
}

debugfln :: proc(format: string, args: ..any) {
	if !config.debug {
		return
	}

	fmt.printfln(format, ..args)
}

