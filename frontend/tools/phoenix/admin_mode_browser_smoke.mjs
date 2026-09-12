import assert from "node:assert/strict";
import {
  evaluate,
  evaluateRecord,
  waitForExpression,
  runBrowserGate,
} from "./federation_browser_smoke.mjs";

const [base, email, activation = "pointer"] = process.argv.slice(2);
assert.ok(base, "base URL is required");
assert.ok(email, "login email is required");
assert.ok(["pointer", "keyboard"].includes(activation));
const origin = new URL(base);
assert.equal(origin.protocol, "http:");
assert.ok(
  ["127.0.0.1", "localhost"].includes(origin.hostname),
  "Use an isolated local test endpoint",
);

await runBrowserGate(["--login-email", email, "--scenario-timeout-ms", "60000"], {
  originUrl: base,
  async runScenarioImpl(client, _diagnostics, _args, { secret, signal }) {
    assert.ok(secret, "login secret is required");
    /** @param {string} expression @param {string} label */
    const inspect = (expression, label) => evaluate(client, expression, label, { signal });
    /** @param {string} expression @param {string} label */
    const waitFor = (expression, label) => waitForExpression(client, expression, label, { signal });
    /** @param {string} selector @param {string} label */
    const click = async (selector, label) => {
      if (activation === "keyboard") {
        await waitFor(`!!document.querySelector(${JSON.stringify(selector)})`, label);
        const { root } = await client.send("DOM.getDocument");
        const { nodeId } = await client.send("DOM.querySelector", {
          nodeId: root.nodeId,
          selector,
        });
        await client.send("DOM.focus", { nodeId });
        await client.send("Input.dispatchKeyEvent", {
          type: "keyDown",
          key: "Enter",
          code: "Enter",
          windowsVirtualKeyCode: 13,
        });
        await client.send("Input.dispatchKeyEvent", {
          type: "keyUp",
          key: "Enter",
          code: "Enter",
          windowsVirtualKeyCode: 13,
        });
        return;
      }
      await waitFor(`!!document.querySelector(${JSON.stringify(selector)})`, label);
      const point = await evaluateRecord(
        client,
        `(() => {
        const element = document.querySelector(${JSON.stringify(selector)});
        const rect = element.getBoundingClientRect();
        const x = rect.x + rect.width / 2;
        const y = rect.y + rect.height / 2;
        return { x, y, visible: rect.width > 0 && rect.height > 0 && element.contains(document.elementFromPoint(x, y)) };
      })()`,
        label + " bounds",
        { signal },
      );
      assert.ok(point.visible, label + " must be visible and unobstructed");
      assert.ok(
        typeof point.x === "number" && typeof point.y === "number",
        "pointer coordinates are required",
      );
      const params = {
        x: point.x,
        y: point.y,
        button: /** @type {const} */ ("left"),
        clickCount: 1,
      };
      await client.send("Input.dispatchMouseEvent", { ...params, type: "mouseMoved" });
      await client.send("Input.dispatchMouseEvent", { ...params, type: "mousePressed" });
      await client.send("Input.dispatchMouseEvent", { ...params, type: "mouseReleased" });
    };
    await client.send("Page.navigate", { url: base + "/sign-in" });
    await waitFor("!!document.querySelector('#sign-in-form')", "sign-in form");
    await inspect(
      `(()=>{const f=document.querySelector('#sign-in-form');f.querySelector('[name="user[email]"]').value=${JSON.stringify(email)};f.querySelector('[name="user[password]"]').value=${JSON.stringify(secret.password)};f.requestSubmit();})()`,
      "sign in",
    );
    await waitFor("!!document.querySelector('#account-desktop-user')", "organization shell");

    await click("#account-desktop-user", "account menu");
    await waitFor(
      "!!document.querySelector('[id^=account-desktop-switch-]')",
      "organization switch",
    );
    const switchId = await inspect(
      "document.querySelector('[id^=account-desktop-switch-]').id",
      "switch form ID",
    );
    assert.ok(typeof switchId === "string", "organization switch ID is required");
    await click(`#${switchId} button`, "switch organization");
    await waitFor(
      `!document.getElementById(${JSON.stringify(switchId)}) && !!document.querySelector('#account-desktop-user')`,
      "organization navigation",
    );
    await click("#account-desktop-user", "switched account menu");
    await waitFor(
      `!!document.querySelector('[id^=account-desktop-switch-]') && !document.getElementById(${JSON.stringify(switchId)})`,
      "updated organization context",
    );
    await waitFor("!!document.querySelector('a[href=\"/admin-mode\"]')", "admin action");
    await click('a[href="/admin-mode"]', "enter admin mode");
    await waitFor("!!document.querySelector('#admin-mode-form')", "admin form");

    await inspect(
      `(()=>{const f=document.querySelector('#admin-mode-form');f.querySelector('[type=password]').value='incorrect-fixture-password';f.requestSubmit();})()`,
      "reject password",
    );
    await waitFor(
      "location.pathname === '/admin-mode' && !!document.querySelector('#admin-mode-form') && document.querySelector('#admin-mode-form [type=password]').value === ''",
      "retry form",
    );
    await waitFor(
      "document.body.textContent.includes('The supplied password was rejected.')",
      "password rejection feedback",
    );

    await inspect(
      `(()=>{const f=document.querySelector('#admin-mode-form');f.querySelector('[type=password]').value=${JSON.stringify(secret.password)};f.requestSubmit();})()`,
      "confirm password",
    );
    await waitFor(
      "location.pathname === '/admin' && !!document.querySelector('#host-page-heading')",
      "admin shell",
    );
    await waitFor(
      "!!document.querySelector('[data-mounted-surface=admin_home]') && document.querySelector('#host-page-heading')?.dataset.pageHeadingSource === 'application'",
      "admin dashboard",
    );

    await click("#account-desktop-user", "account menu");
    await waitFor("!!document.querySelector('#account-desktop-leave-admin')", "leave admin form");
    await click("#account-desktop-leave-admin button", "leave admin mode");
    await waitFor(
      "location.pathname === '/' && !!document.querySelector('#account-desktop-user')",
      "ordinary shell",
    );

    await click("#account-desktop-user", "account menu");
    await waitFor("!!document.querySelector('#account-desktop-sign-out')", "sign-out form");
    await click("#account-desktop-sign-out button", "sign out");
    await waitFor(
      "location.pathname === '/sign-in' && !!document.querySelector('#sign-in-form')",
      "signed-out form",
    );
    return { adminMode: "passed", nativeSessionForms: "passed", activation };
  },
});
console.log("Admin mode browser smoke passed");
