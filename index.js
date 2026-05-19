import "dotenv/config";
import * as cheerio from "cheerio";

const COOKIE = process.env.OPENCODE_COOKIE;

if (!COOKIE) {
    console.error("Set OPENCODE_COOKIE env variable to your auth cookie value");
    process.exit(1);
}

const res = await fetch("https://opencode.ai/workspace/wrk_01ExampleWorkspaceID12345678/go", {
    headers: {
        cookie: COOKIE,
        "user-agent":
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36",
    },
});

if (!res.ok) {
    console.error(`Failed to fetch: ${res.status} ${res.statusText}`);
    process.exit(1);
}

const html = await res.text();
const $ = cheerio.load(html);

const usage = [];

$("[data-slot='usage-item']").each((_, el) => {
    const label = $(el).find("[data-slot='usage-label']").text().trim();
    const value = $(el).find("[data-slot='usage-value']").text().trim();
    const reset = $(el).find("[data-slot='reset-time']").text().trim();
    const width = $(el).find("[data-slot='progress-bar']").attr("style") ?? "";
    const percent = parseInt(width.match(/width:\s*(\d+)/)?.[1] ?? "0");
    usage.push({ label, value, percent, reset });
});

if (usage.length === 0) {
    console.error("No usage data found — cookie may be expired or selector changed");
    process.exit(1);
}

const useJson = process.argv.includes("--json");

if (useJson) {
    console.log(JSON.stringify(usage));
} else {
    console.log("\nOpenCode Go Usage\n" + "=".repeat(40));
    for (const { label, percent, reset } of usage) {
        const filled = Math.round(percent / 5);
        const bar = "█".repeat(filled) + "░".repeat(20 - filled);
        console.log(`\n${label}`);
        console.log(`[${bar}] ${percent}%`);
        console.log(`${reset}`);
    }
    console.log();
}