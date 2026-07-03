/**
 * Test-only helper extension.
 *
 * Registers a flag --emit-big that writes a payload LARGER than the OS pipe
 * buffer (~64KB) to stdout using the SAME technique the real extension uses,
 * then exits. This is a focused regression guard for the ">64KB fs.writeSync
 * partial write truncates piped output" bug: the payload must arrive intact
 * when piped (e.g. `... | wc -c`).
 *
 * It intentionally does NOT depend on how many tools are installed.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";

// Keep this in sync with list-tools.ts writeOut(): loop until every byte is
// flushed, retrying on EAGAIN. If this helper regressed to a single
// fs.writeSync(1, big) the piped byte count would fall short of TARGET.
function writeOut(s: string): void {
	const buf = Buffer.from(s.endsWith("\n") ? s : s + "\n", "utf8");
	let offset = 0;
	while (offset < buf.length) {
		try {
			offset += fs.writeSync(1, buf, offset, buf.length - offset);
		} catch (err: any) {
			if (err && err.code === "EAGAIN") continue;
			throw err;
		}
	}
}

const TARGET = 200_000; // well past the ~64KB pipe buffer

export default function bigEmitter(pi: ExtensionAPI) {
	pi.registerFlag("emit-big", {
		description: "Test helper: emit a >64KB payload to stdout and exit",
		type: "boolean",
		default: false,
	});
	pi.on("session_start", async () => {
		if (!pi.getFlag("emit-big")) return;
		// A single line of known length; last chars are a sentinel we assert on.
		const filler = "x".repeat(TARGET - 16) + "END_OF_BIG_EMIT\n";
		writeOut(filler);
		process.exit(0);
	});
}
