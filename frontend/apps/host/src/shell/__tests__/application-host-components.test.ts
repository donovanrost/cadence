import { createApp, nextTick } from "vue";
import assert from "node:assert/strict";
import { test } from "vite-plus/test";
import { installDom, required } from "../../../../../test-support/mounted-contract";
import ApplicationHost from "../ApplicationHost.vue";
const applicationHost = { default: ApplicationHost };
test("application host components behavior", async () => {
  const dom = installDom();
  const props = {
    host: {
      dom_id: "mission-application-host",
      application_key: "limits",
      application_version: 1,
      application_installation_id: "application-installation-1",
      surface_id: "activity",
      renderer: "declarative",
    },
    navigation: {
      id: "application-surface-navigation",
      label: "Application surfaces",
      items: [
        {
          id: "application-surface-nav-manage",
          surface_id: "manage",
          label: "Definitions",
          href: "/missions/mission-1/applications/limits/manage",
          current: false,
        },
        {
          id: "application-surface-nav-activity",
          surface_id: "activity",
          label: "Current posture",
          href: "/missions/mission-1/applications/limits/activity",
          current: true,
        },
      ],
    },
    declarative_surface: {
      id: "declarative-application-surface",
      page: { title: "Current limit posture", subtitle: null },
      action_feedback: null,
      stats: [
        {
          id: "application-surface-stat-red",
          stat_id: "red",
          label: "Red departures",
          value: "1",
          tone: "blocked",
          tone_label: "Missing",
        },
        {
          id: "application-surface-stat-nominal",
          stat_id: "nominal",
          label: "Nominal points",
          value: "12",
          tone: "ready",
          tone_label: "Ready",
        },
      ],
      diagnostics: {
        id: "limit-current-diagnostics",
        items_id: "limit-current-diagnostics-items",
        role: "alert",
        severity: "error",
        count: 2,
        total_count: 3,
        count_label: "2 shown · 3 total",
        label: "Blocked",
        title: "Current limit findings",
        description: "Resolve current departures.",
        items: [
          {
            id: "limit-current-diagnostics-item-red",
            diagnostic_id: "red",
            code: "limits.current.red",
            severity: "error",
            title: "Red limit departures",
            detail: "One point is beyond a red threshold.",
            value: "HK.bus_voltage",
          },
          {
            id: "limit-current-diagnostics-item-advisory",
            diagnostic_id: "advisory",
            code: "limits.current.advisory",
            severity: "warning",
            title: "Advisory posture",
            detail: "Review the configured threshold.",
            value: null,
          },
        ],
      },
      form: null,
      packet_bindings: null,
      table: null,
      activity: null,
    },
    application_surface_rows: [],
    application_surface_activity: [],
    application_surface_packet_groups: [],
  };
  const frozenProps = structuredClone(props);
  const expectedHtml = {
    "#application-surface-navigation":
      '<nav id="application-surface-navigation" aria-label="Application surfaces" class="mb-5 flex flex-wrap items-center gap-1 border-b border-base-300/70"><a id="application-surface-nav-manage" href="/missions/mission-1/applications/limits/manage" data-phx-link="redirect" data-phx-link-state="push" class="relative -mb-px border-b-2 px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition-colors border-transparent text-base-content/55 hover:border-base-content/30 hover:text-base-content">Definitions</a><a id="application-surface-nav-activity" href="/missions/mission-1/applications/limits/activity" data-phx-link="redirect" data-phx-link-state="push" aria-current="page" class="relative -mb-px border-b-2 px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition-colors border-primary text-primary">Current posture</a></nav>',
    "#application-surface-stats":
      '<section id="application-surface-stats" class="grid gap-4 md:grid-cols-3"><section id="application-surface-stat-red" class="card border border-base-300 bg-base-200"><div class="card-body p-6"><div class="flex items-start justify-between gap-3"><div><p class="hud-label">Red departures</p><p class="mt-2 text-2xl font-semibold">1</p></div><span class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-error/20 text-error">Missing</span></div></div></section><section id="application-surface-stat-nominal" class="card border border-base-300 bg-base-200"><div class="card-body p-6"><div class="flex items-start justify-between gap-3"><div><p class="hud-label">Nominal points</p><p class="mt-2 text-2xl font-semibold">12</p></div><span class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-success/20 text-success">Ready</span></div></div></section></section>',
    "#limit-current-diagnostics":
      '<section id="limit-current-diagnostics" role="alert" aria-live="polite" data-diagnostic-severity="error" data-diagnostic-count="2" data-diagnostic-total="3" class="overflow-hidden border border-base-300/80 bg-base-200/30"><header class="grid gap-4 border-b border-base-300/70 px-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center"><div class="grid size-9 place-items-center border border-error/35 bg-error/10 text-error"><span class="size-4 hero-exclamation-triangle" aria-hidden="true"></span></div><div class="min-w-0"><div class="flex flex-wrap items-center gap-x-3 gap-y-1"><h2 class="text-sm font-semibold uppercase tracking-[0.14em]">Current limit findings</h2><span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">2 shown · 3 total</span></div><p class="mt-1 text-sm text-base-content/65">Resolve current departures.</p></div><span class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide bg-error/20 text-error">Blocked</span></header><div id="limit-current-diagnostics-items" class="divide-y divide-base-300/60"><article id="limit-current-diagnostics-item-red" data-diagnostic-code="limits.current.red" data-diagnostic-severity="error" class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"><span class="rounded-full bg-error"></span><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">limits.current.red</span><h3 class="text-sm font-medium text-base-content">Red limit departures</h3></div><p class="mt-1 text-xs leading-5 text-base-content/60">One point is beyond a red threshold.</p></div><div class="flex items-center gap-3 self-center"><span class="max-w-56 truncate font-mono text-xs text-base-content/65">HK.bus_voltage</span><span class="size-4 shrink-0 hero-x-circle text-error" aria-hidden="true"></span></div></article><article id="limit-current-diagnostics-item-advisory" data-diagnostic-code="limits.current.advisory" data-diagnostic-severity="warning" class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"><span class="rounded-full bg-warning"></span><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">limits.current.advisory</span><h3 class="text-sm font-medium text-base-content">Advisory posture</h3></div><p class="mt-1 text-xs leading-5 text-base-content/60">Review the configured threshold.</p></div><div class="flex items-center gap-3 self-center"><!--v-if--><span class="size-4 shrink-0 hero-exclamation-circle text-warning" aria-hidden="true"></span></div></article></div></section>',
  };
  const app = createApp(applicationHost.default, props);
  app.mount(required(dom.window.document.querySelector("#app")));
  await nextTick();

  for (const [selector, html] of Object.entries(expectedHtml)) {
    const element = required(dom.window.document.querySelector(selector));
    assert.ok(element, `${selector} remains rendered by the composed host`);
    assert.equal(element.outerHTML, html, `${selector} keeps its exact frozen native DOM shape`);
  }

  assert.deepEqual(
    props,
    frozenProps,
    "the display components do not mutate Phoenix presentation DTOs",
  );
  assert.equal(
    required(dom.window.document.querySelector("#application-surface-navigation")).parentElement,
    required(dom.window.document.querySelector("#declarative-application-surface")).parentElement,
    "application navigation adds no wrapper",
  );
  assert.equal(
    required(
      required(dom.window.document.querySelector("#application-surface-stats")).parentElement,
    ).id,
    "declarative-application-surface",
    "application stats add no wrapper",
  );
  assert.equal(
    required(
      required(dom.window.document.querySelector("#limit-current-diagnostics")).parentElement,
    ).id,
    "declarative-application-surface",
    "application diagnostics add no wrapper",
  );
  assert.doesNotThrow(() => app.unmount());

  console.log("application host component contracts passed");
});
