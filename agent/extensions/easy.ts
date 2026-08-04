import { readFileSync } from "node:fs";

const AGENT_CONFIG_URL = new URL("../config.yml", import.meta.url);
const THINKING_LEVELS = new Set([
	"off",
	"minimal",
	"low",
	"medium",
	"high",
	"xhigh",
	"max",
	"auto",
]);

function loadSmolThinkingLevel(): string | undefined {
	let config: string;
	try {
		config = readFileSync(AGENT_CONFIG_URL, "utf8");
	} catch {
		return undefined;
	}

	const role = config.match(/^\s+smol:\s+(.+?)\s*$/m);
	if (!role) return undefined;
	const spec = role[1].replace(/^(["'])(.*)\1$/, "$2");
	const separator = spec.lastIndexOf(":");
	if (separator === -1) return undefined;

	const suffix = spec.slice(separator + 1).toLowerCase();
	return THINKING_LEVELS.has(suffix) ? suffix : undefined;
}

export default function easyExtension(pi: any): void {
	pi.registerCommand("easy", {
		description: "Switch to the smol role; optionally run a task",
		handler: async (args: string, ctx: any) => {
			const model = ctx.models.resolve("@smol");
			if (!model) {
				ctx.ui.notify("The smol role has no available model", "error");
				return;
			}

			await ctx.waitForIdle();
			const switched = await pi.setModel(model);
			if (!switched) {
				ctx.ui.notify("The smol role model is not authenticated", "error");
				return;
			}
			const thinking = loadSmolThinkingLevel();
			if (thinking) pi.setThinkingLevel(thinking);

			const selector = `${model.provider}/${model.id}${
				thinking ? `:${thinking}` : ""
			}`;
			ctx.ui.notify(`Easy model active: ${selector}`, "info");

			const prompt = args.trim();
			if (prompt.length > 0) pi.sendUserMessage(prompt);
		},
	});
}
