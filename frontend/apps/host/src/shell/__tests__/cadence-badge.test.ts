import { createApp, defineComponent, h, nextTick } from "vue";
import assert from "node:assert/strict";
import { test } from "vite-plus/test";
import { installDom, required, flushVue } from "../../../../../test-support/mounted-contract";
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import StatusBadge from "../StatusBadge.vue";
test("cadence badge behavior", async () => {
  const dom = installDom();
  const baseClasses =
    "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide";
  const cadenceToneClasses = {
    info: "bg-info/20 text-info",
    success: "bg-success/20 text-success",
    warning: "bg-warning/20 text-warning",
    error: "bg-error/20 text-error",
  };
  const statusToneClasses = {
    info: cadenceToneClasses.info,
    ready: cadenceToneClasses.success,
    attention: cadenceToneClasses.warning,
    blocked: cadenceToneClasses.error,
  };
  const RuntimeOracle = defineComponent({
    name: "CadenceBadgeRuntimeOracle",
    setup() {
      return () =>
        h("main", { id: "badge-contracts" }, [
          ...(["info", "success", "warning", "error"] as const).map((tone) =>
            h(
              CadenceBadge,
              {
                id: `cadence-badge-${tone}`,
                tone,
                "data-expected-classes": cadenceToneClasses[tone],
              },
              { default: () => `${tone} primitive` },
            ),
          ),
          ...(["info", "ready", "attention", "blocked"] as const).map((status) =>
            h(StatusBadge, {
              id: `status-badge-${status}`,
              status,
              label: `${status} status`,
            }),
          ),
          h(StatusBadge, {
            id: "status-badge-default",
            label: "<default & safe>",
          }),
        ]);
    },
  });

  const app = createApp(RuntimeOracle);
  app.mount(required(dom.window.document.querySelector("#app")));
  await flushVue(nextTick);

  const root = required(dom.window.document.querySelector("#badge-contracts"));
  assert.equal(root.children.length, 9);

  for (const [tone, toneClasses] of Object.entries(cadenceToneClasses)) {
    const badge = required(dom.window.document.querySelector(`#cadence-badge-${tone}`));

    assert.equal(badge.tagName, "SPAN");
    assert.equal(badge.className, `${baseClasses} ${toneClasses}`);
    assert.equal(badge.textContent, `${tone} primitive`);
    assert.equal(badge.getAttribute("data-expected-classes"), toneClasses);
  }

  for (const [status, toneClasses] of Object.entries(statusToneClasses)) {
    const badge = required(dom.window.document.querySelector(`#status-badge-${status}`));

    assert.equal(badge.tagName, "SPAN");
    assert.equal(badge.className, `${baseClasses} ${toneClasses}`);
    assert.equal(badge.textContent, `${status} status`);
  }

  const defaultBadge = required(dom.window.document.querySelector("#status-badge-default"));
  assert.equal(defaultBadge.tagName, "SPAN");
  assert.equal(defaultBadge.className, `${baseClasses} ${cadenceToneClasses.info}`);
  assert.equal(defaultBadge.textContent, "<default & safe>");
  assert.equal(defaultBadge.innerHTML, "&lt;default &amp; safe&gt;");
  assert.doesNotThrow(() => app.unmount());
});
