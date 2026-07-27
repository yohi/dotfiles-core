// scripts/workers/install.js
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const allowedPaths = ["/", "/install.sh"];
    if (request.method !== "GET" || !allowedPaths.includes(url.pathname)) {
      return new Response("Not Found", { status: 404 });
    }

    const { GITHUB_REPO, GITHUB_REF, SCRIPT_PATH, EXPECTED_PREFIX, EXPECTED_MARKER } = env;
    if (!GITHUB_REPO || !GITHUB_REF || !SCRIPT_PATH) {
      return new Response("Missing configuration", { status: 500 });
    }

    const rawUrl = `https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_REF}/${SCRIPT_PATH}`;

    let script;
    try {
      const resp = await fetch(rawUrl, {
        headers: { "User-Agent": "dotfiles-bootstrap-worker" },
      });
      if (!resp.ok) {
        return new Response("Failed to fetch script from GitHub", { status: 503 });
      }
      script = await resp.text();
    } catch (e) {
      return new Response("Failed to fetch script from GitHub", { status: 503 });
    }

    const prefix = EXPECTED_PREFIX || "#!/bin/bash";
    const marker = EXPECTED_MARKER || "# dotfiles-bootstrap";
    if (
      script.length === 0 ||
      !script.startsWith(prefix) ||
      !script.includes(marker)
    ) {
      return new Response("Script integrity check failed", { status: 500 });
    }

    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(script)
    );
    const hashArray = Array.from(new Uint8Array(digest));
    const hashHex = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");

    return new Response(script, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "public, max-age=300",
        "X-Script-SHA256": hashHex,
      },
    });
  },
};
