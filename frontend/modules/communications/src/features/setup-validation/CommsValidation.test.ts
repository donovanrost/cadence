import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import CommsValidation from "./CommsValidation.vue";

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
};

describe("grouped finding DOM identities", () => {
  it("scopes repeated and missing IDs to their group", () => {
    const wrapper = mount(CommsValidation, { props: { validation } });
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
  });
});
