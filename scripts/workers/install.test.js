// scripts/workers/install.test.js
import test from "node:test";
import assert from "node:assert";
import { createFetchMock, Miniflare } from "miniflare";

const fixtureScript = "#!/bin/bash\n# dotfiles-bootstrap\necho bootstrap\n";
function createWorker(status = 200, body = fixtureScript) {
  const fetchMock = createFetchMock();
  fetchMock.disableNetConnect();
  fetchMock
    .get("https://raw.githubusercontent.com")
    .intercept({
      path: "/yohi/dotfiles-core/master/scripts/bootstrap.sh",
      method: "GET",
    })
    .reply(status, body);

  return new Miniflare({
    modules: true,
    scriptPath: "./scripts/workers/install.js",
    compatibilityDate: "2025-01-01",
    fetchMock,
    bindings: {
      GITHUB_REPO: "yohi/dotfiles-core",
      GITHUB_REF: "master",
      SCRIPT_PATH: "scripts/bootstrap.sh",
      EXPECTED_PREFIX: "#!/bin/bash",
      EXPECTED_MARKER: "# dotfiles-bootstrap",
    },
  });
}

test("returns 404 for unknown paths", async () => {
  const mf = createWorker();
  const res = await mf.dispatchFetch("https://example.com/");
  assert.strictEqual(res.status, 404);
});

test("returns 200 with sha256 header for install.sh", async () => {
  const mf = createWorker();
  const res = await mf.dispatchFetch("https://example.com/install.sh");
  assert.strictEqual(res.status, 200);
  assert.strictEqual(
    res.headers.get("X-Script-SHA256"),
    "8fb9f701c258969600e289e52cc070e09d52645f0d0463bf2559140d5ad6ee63"
  );
  const body = await res.text();
  assert.strictEqual(body, fixtureScript);
});

test("returns 503 when GitHub cannot provide the script", async () => {
  const mf = createWorker(502, "upstream failure");
  const res = await mf.dispatchFetch("https://example.com/install.sh");
  assert.strictEqual(res.status, 503);
});

test("returns 500 when the script fails integrity validation", async () => {
  const mf = createWorker(200, "echo invalid");
  const res = await mf.dispatchFetch("https://example.com/install.sh");
  assert.strictEqual(res.status, 500);
});
