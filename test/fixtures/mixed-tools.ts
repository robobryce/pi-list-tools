import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function mixedTools(pi: ExtensionAPI) {
	pi.registerTool({
		name: "aaa_fixture_tool",
		label: "AAA Fixture Tool",
		description: "AAA fixture.",
		parameters: { type: "object", properties: {}, additionalProperties: false },
		async execute() {
			return { content: [{ type: "text", text: "aaa" }], details: {} };
		},
	});

	pi.registerTool({
		name: "zzz_fixture_tool",
		label: "ZZZ Fixture Tool",
		description: "ZZZ fixture.",
		parameters: { type: "object", properties: {}, additionalProperties: false },
		async execute() {
			return { content: [{ type: "text", text: "zzz" }], details: {} };
		},
	});
}
