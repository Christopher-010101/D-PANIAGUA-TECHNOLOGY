const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const adminScript = fs.readFileSync(path.join(__dirname, "..", "js", "admin.js"), "utf8");
const sandbox = {
  window: { DP: { db: null } },
  document: { querySelector: () => ({ textContent: "", classList: { remove() {}, add() {} } }) },
  console
};
vm.runInNewContext(adminScript, sandbox, { filename: "js/admin.js" });

test("admin users errors show the JSON message returned by the Edge Function", async () => {
  const response = new Response(JSON.stringify({ error: "Acceso denegado: solo administradores activos." }), {
    status: 403,
    headers: { "Content-Type": "application/json" }
  });
  const message = await sandbox.window.DP.getEdgeFunctionErrorMessage({
    data: null,
    error: { message: "Edge Function returned a non-2xx status code", context: response }
  });

  assert.equal(message, "Acceso denegado: solo administradores activos.");
});

test("admin users errors retain a useful fallback without a response body", async () => {
  const message = await sandbox.window.DP.getEdgeFunctionErrorMessage({
    data: null,
    error: { message: "Edge Function returned a non-2xx status code" }
  });

  assert.equal(message, "Edge Function returned a non-2xx status code");
});
