import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import CommsCanonicalSurface from "./CommsCanonicalSurface.vue";
import CommsOverview from "./CommsOverview.vue";
import CommsValidation from "./CommsValidation.vue";
import type { CommsOverview as Overview } from "./comms-overview";

const groups = ["spacecraft", "transport"].map((owner) => ({
  id: `comms-validation-${owner}`,
  title: owner,
  description: "Configuration checks",
  findings: ["finding-1", null].map((id, index) => ({
    id,
    title: `${owner} finding ${index + 1}`,
    body: "Review configuration",
    action_label: "Review",
    action_href: `/missions/mission-1/comms/${owner}`,
    severity: "Warning",
    status: { tone: "attention" as const, label: "Warning" },
  })),
}));

const validation = {
  id: "comms-validation-page",
  title: "Validation",
  subtitle: "Configuration checks",
  description: "Configuration checks",
  eyebrow: "Checks",
  breadcrumbs: [],
  finding_count_suffix: "4 findings",
  status: { tone: "attention" as const, label: "Attention" },
  empty: false,
  empty_state: { id: "empty", title: "All clear", description: "No findings" },
  findings_id: "comms-validation-findings",
  finding_groups: groups,
  pagination: { label: "1–4 of 4", previousHref: null, nextHref: null },
};

const overview: Overview = {
  validation,
  transport: {
    id: "comms-transports",
    eyebrow: "Transport",
    count: 0,
    count_label: "configured",
    description: "Mission transports",
    status: { tone: "attention", label: "Attention" },
    empty: true,
    empty_state: {
      title: "No transports",
      description: "Configure a transport",
      action_label: "Add",
      action_href: "/transports/new",
    },
    rows: [],
    manage_label: "Manage",
    manage_href: "/transports",
    add_label: "Add",
    add_href: "/transports/new",
  },
};

const renderers = {
  canonical: () =>
    mount(CommsCanonicalSurface, {
      props: {
        surfaceId: "validation",
        version: 1,
        context: { missionId: "mission-1" },
        payload: {
          navigation: { fallback_href: "/missions/mission-1/comms/validation", breadcrumbs: [] },
          data: {
            ...validation,
            status: "attention",
            finding_count: 4,
            total_count: 4,
            page: 1,
            page_size: 20,
            page_count: 1,
            findings: groups.flatMap((group) => group.findings),
          },
        },
      },
    }),
  overview: () => mount(CommsOverview, { props: { overview } }),
  validation: () => mount(CommsValidation, { props: { validation } }),
};

describe("grouped finding DOM identities", () => {
  it.each(Object.entries(renderers))(
    "%s scopes repeated and missing IDs to their group",
    (_name, render) => {
      const wrapper = render();
      try {
        const ids = wrapper.findAll("[id]").map((element) => element.attributes("id"));
        expect(new Set(ids).size).toBe(ids.length);
        for (const group of groups) {
          for (const [index, finding] of group.findings.entries()) {
            const row = wrapper.get(`#${group.id}-${finding.id ?? `finding-${index + 1}`}`);
            expect(row.get("h3").text()).toBe(finding.title);
            expect(row.get("a").attributes("href")).toBe(finding.action_href);
            expect(row.get("a").attributes("data-phx-link")).toBe("redirect");
          }
        }
      } finally {
        wrapper.unmount();
      }
    },
  );
});
