import fs from "node:fs/promises";
import path from "node:path";
import { tmpdir } from "node:os";

const LOG_DIR = path.join(tmpdir(), "ccr-router-logs");

async function ensureDir() {
    try {
        await fs.mkdir(LOG_DIR, { recursive: true });
    } catch {}
}

export interface RouterLogEntry {
    sessionId: string;
    timestamp: number;
    taskType: string;
    model: string;
}

export async function logRouterEvent(entry: RouterLogEntry) {
    try {
        await ensureDir();

        const file = path.join(LOG_DIR, `session-${entry.sessionId}.json`);

        let existing: RouterLogEntry[] = [];

        try {
            const content = await fs.readFile(file, "utf-8");
            existing = JSON.parse(content);
        } catch {}

        existing.push(entry);

        // Keep last 100 entries only
        const trimmed = existing.slice(-100);

        await fs.writeFile(file, JSON.stringify(trimmed, null, 2));
    } catch {}
}
