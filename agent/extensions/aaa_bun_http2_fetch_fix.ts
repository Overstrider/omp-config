/**
 * Bun 1.3.x native fetch intermittently crashes on HTTP/2 to api2.cursor.sh
 * (the cursor provider's token exchange), throwing:
 *   TypeError: The "authority" argument must be of type string ... Received type number
 * Route requests to that host through Node's http/1.1 client instead of Bun's
 * buggy native fetch. Everything else passes through unchanged.
 */
import https from "node:https";

const origFetch = globalThis.fetch;
const AFFECTED = new Set(["api2.cursor.sh"]);

function normalizeHeaders(init: any): Record<string, string> {
  const h: Record<string, string> = {};
  const src = init?.headers;
  if (!src) return h;
  if (typeof src.forEach === "function" && !Array.isArray(src)) {
    src.forEach((v: string, k: string) => { h[k] = v; });
  } else if (Array.isArray(src)) {
    for (const [k, v] of src) h[k] = String(v);
  } else {
    for (const k of Object.keys(src)) h[k] = String(src[k]);
  }
  return h;
}

function nodeHttp1Fetch(url: string, init: any): Promise<Response> {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      { hostname: u.hostname, port: 443, path: u.pathname + u.search, method: (init?.method || "GET").toUpperCase(), headers: normalizeHeaders(init), ALPNProtocols: ["http/1.1"] },
      (res) => {
        const chunks: Buffer[] = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const buf = Buffer.concat(chunks);
          const safe: Record<string, string> = {};
          for (const [k, v] of Object.entries(res.headers)) { if (typeof v === "string") safe[k] = v; else if (Array.isArray(v)) safe[k] = v.join(", "); }
          try { resolve(new Response(buf, { status: res.statusCode || 200, statusText: res.statusMessage || "", headers: safe })); }
          catch { resolve(new Response(buf, { status: res.statusCode || 200 })); }
        });
      },
    );
    req.on("error", reject);
    const body = init?.body;
    if (body != null) req.write(typeof body === "string" || Buffer.isBuffer(body) ? body : Buffer.from(body));
    req.end();
  });
}

globalThis.fetch = ((input: any, init?: any) => {
  let url: string | undefined;
  try { url = typeof input === "string" ? input : (input?.url ?? String(input)); } catch {}
  try { if (url && AFFECTED.has(new URL(url).hostname)) return nodeHttp1Fetch(url, init ?? (typeof input === "object" ? input : undefined)); } catch {}
  return origFetch(input, init);
}) as typeof fetch;

export default async function (_pi: unknown): Promise<void> {}
