package http

import "core:flags"
import "core:fmt"
import "core:mem"
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

tracker: mem.Tracking_Allocator

// Wraps the current context allocator in a tracking allocator. The caller has to assign the
// returned allocator to `context.allocator`, because the context is per-procedure and any change
// made here would only be visible to this proc and its callees.
init_tracking_allocator :: proc() -> mem.Allocator {
	mem.tracking_allocator_init(&tracker, context.allocator)

	return mem.tracking_allocator(&tracker)
}

// Reports whatever the tracking allocator still holds and tears it down.
report_tracked_leaks :: proc() {
	if len(tracker.allocation_map) > 0 {
		fmt.eprintfln("%v allocations were not freed:", len(tracker.allocation_map))

		for _, entry in tracker.allocation_map {
			fmt.eprintfln("Leaked %v bytes at %v", entry.size, entry.location)
		}
	}

	mem.tracking_allocator_destroy(&tracker)
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

