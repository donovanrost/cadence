import { describe, expect, it, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import SpacecraftConfigurationPage from "./SpacecraftConfigurationPage.vue";
import ConfigurationChanges from "./ConfigurationChanges.vue";
import { createConfigurationDrafts } from "./drafts";
import {
  createConfigurationPort,
  readConfiguration,
  type ConfigurationPort,
  type ConfigurationSnapshot,
} from "./contracts";
import { configurationFixture } from "./fixtures.test-support";
import { configurationChanges } from "./presentation";

describe("spacecraft configuration", () => {
  it.each(["direct", "independent"] as const)(
    "shows progress and rejected %s submissions beside the activation controls",
    async (requirement) => {
      const initial = configurationFixture();
      const snapshot: ConfigurationSnapshot = {
        ...initial,
        section: "changes",
        fleet: initial.fleet.map((item) => ({
          ...item,
          href: item.href.replace("section=overview", "section=changes"),
        })),
        saved_version: 1,
        document: {
          ...initial.document,
          catalog_revision_id: "catalog-1",
          commanding_enabled: true,
        },
        approval: { ...initial.approval, requirement },
      };
      const drafts = createConfigurationDrafts();
      drafts.receive(snapshot).feedback = "Draft saved.";
      let finish = () => {};
      const pending = new Promise<void>((resolve) => {
        finish = resolve;
      });
      const message =
        "The active fleet configuration changed. Review the latest state and submit again.";
      const send = vi.fn(async () => {
        await pending;
        return { status: "rejected", message };
      });
      const wrapper = mount(SpacecraftConfigurationPage, {
        props: {
          data: snapshot,
          identity: {
            organizationId: "org-1",
            missionId: "mission-1",
            spacecraftId: "spacecraft-1",
          },
          port: createConfigurationPort(send),
          drafts,
        },
      });
      try {
        const panel = wrapper.get("#spacecraft-configuration-review");
        const button = panel.get(
          requirement === "direct" ? "#spacecraft-activate" : "#spacecraft-submit-review",
        );
        await button.trigger("click");
        expect(send).toHaveBeenCalledWith(requirement === "direct" ? "activate" : "review", {
          token: snapshot.token,
          policy_token: snapshot.approval.token,
        });
        expect(button.attributes("aria-busy")).toBe("true");
        expect(button.attributes("disabled")).toBeDefined();
        expect(button.text()).toBe(
          requirement === "direct" ? "Activating configuration…" : "Submitting for review…",
        );
        expect(panel.find("#spacecraft-activation-feedback").exists()).toBe(false);
        finish();
        await flushPromises();
        expect(panel.get('#spacecraft-activation-feedback[role="status"]').text()).toBe(message);
        expect(wrapper.findAll("#spacecraft-activation-feedback")).toHaveLength(1);
        expect(button.attributes("disabled")).toBeUndefined();
        expect(button.attributes("aria-busy")).toBeUndefined();
        expect(drafts.receive(snapshot).draft).toEqual(snapshot.document);
        expect(panel.get(`a[href="${snapshot.catalogs[0]?.href}"]`).text()).toBe("View catalog");
      } finally {
        finish();
        wrapper.unmount();
      }
    },
  );
  it("requires a fresh rationale when a live update replaces the review evidence", async () => {
    const snapshot: ConfigurationSnapshot = {
      ...configurationFixture(),
      saved_version: 1,
      review: { id: "request-1", state: "approval_pending", version: 1, requester_id: "teammate" },
    };
    const wrapper = mount(ConfigurationChanges, {
      props: {
        snapshot,
        draft: snapshot.document,
        unsaved: false,
        issues: [],
        busy: false,
        conflict: false,
        feedback: null,
      },
    });
    const rationale = wrapper.get<HTMLTextAreaElement>("#spacecraft-review-reason");
    await rationale.setValue("Checked this revision.");
    await wrapper.setProps({ snapshot: { ...snapshot, name: "Updated display name" } });
    expect(rationale.element.value).toBe("Checked this revision.");
    await wrapper.setProps({
      snapshot: {
        ...snapshot,
        token: "c".repeat(64),
        saved_version: 2,
        review: {
          id: "request-2",
          state: "approval_pending",
          version: 2,
          requester_id: "teammate",
        },
      },
    });
    expect(rationale.element.value).toBe("");
    expect(
      wrapper.get('#spacecraft-review-decision button[type="submit"]').attributes("disabled"),
    ).toBeDefined();
    wrapper.unmount();
  });
  it("keeps different catalog and packet source identities visible when their labels match", () => {
    const initial = configurationFixture();
    const catalog = initial.catalogs[0];
    if (!catalog) throw new Error("Expected a catalog fixture");
    const document = {
      ...initial.document,
      catalog_revision_id: catalog.id,
      telemetry_source_endpoint_id: "source-old",
    };
    const snapshot = {
      ...initial,
      active: { version: 1, generation: 1, document },
      catalogs: [catalog, { ...catalog, id: "catalog-other" }],
      sources: [
        { id: "source-old", name: "Primary" },
        { id: "source-new", name: "Primary" },
      ],
    };
    const changes = configurationChanges(snapshot, {
      ...document,
      catalog_revision_id: "catalog-other",
      telemetry_source_endpoint_id: "source-new",
    });
    expect(changes.map((change) => change.label)).toEqual([
      "Flight software catalog",
      "Packet input",
    ]);
    expect(changes.every((change) => change.before !== change.after)).toBe(true);
  });
  it("adopts a confirmed save with a server-created packet source without discarding another spacecraft's edits", () => {
    const cache = createConfigurationDrafts(),
      initial = configurationFixture();
    const current = cache.receive(initial),
      other = cache.receive(configurationFixture("spacecraft-2"));
    current.draft = {
      ...current.draft,
      catalog_revision_id: "catalog-1",
      telemetry_enabled: true,
      handled_apids: [42],
    };
    other.draft = { ...other.draft, commanding_enabled: true };
    const saved = {
      ...initial,
      saved_version: 1,
      token: "b".repeat(64),
      document: { ...current.draft, telemetry_source_endpoint_id: "source-created" },
    };
    cache.receive(saved);
    expect(current.conflict).toBe(true);
    cache.acceptSaved(saved);
    expect(current.conflict).toBe(false);
    expect(current.draft.telemetry_source_endpoint_id).toBe("source-created");
    expect(cache.changed(initial.spacecraft_id)).toBe(false);
    expect(other.draft.commanding_enabled).toBe(true);
    expect(cache.changed("spacecraft-2")).toBe(true);
  });
  it("retains independent edits across spacecraft and reconciles competing saved changes", () => {
    const cache = createConfigurationDrafts(),
      first = configurationFixture(),
      second = configurationFixture("spacecraft-2");
    const one = cache.receive(first);
    one.draft = { ...one.draft, catalog_revision_id: "catalog-1", commanding_enabled: true };
    const two = cache.receive(second);
    two.draft = { ...two.draft, telemetry_enabled: true };
    expect(cache.receive(first)).toBe(one);
    expect(one.draft.commanding_enabled).toBe(true);
    expect(two.draft.catalog_revision_id).toBeNull();
    const server = {
      ...first,
      token: "b".repeat(64),
      saved_version: 1,
      document: { ...first.document, telemetry_enabled: true },
    };
    cache.receive(server);
    expect(one.conflict).toBe(true);
    expect(one.token).toBe(first.token);
    expect(one.draft.commanding_enabled).toBe(true);
    expect(cache.hasUnsaved()).toBe(true);
    cache.clear();
    expect(cache.hasUnsaved()).toBe(false);
  });
  it("receives an activation with unchanged desired settings without erasing edits", () => {
    const cache = createConfigurationDrafts(),
      snapshot = configurationFixture();
    const session = cache.receive(snapshot);
    session.draft = { ...session.draft, commanding_enabled: true };
    cache.receive({ ...snapshot, token: "b".repeat(64) });
    expect(session.conflict).toBe(false);
    expect(session.draft.commanding_enabled).toBe(true);
    expect(session.token).toBe("b".repeat(64));
  });
  it("decodes scoped destinations and rejects duplicated sources and invalid framing", () => {
    const snapshot = configurationFixture();
    expect(readConfiguration(snapshot).spacecraft_id).toBe("spacecraft-1");
    expect(() =>
      readConfiguration(snapshot, {
        organizationId: "other-org",
        missionId: "mission-1",
        spacecraftId: "spacecraft-1",
      }),
    ).toThrow();
    expect(() =>
      readConfiguration({ ...snapshot, sources: [...snapshot.sources, ...snapshot.sources] }),
    ).toThrow();
    expect(() =>
      readConfiguration({
        ...snapshot,
        links: { ...snapshot.links, identity: "/missions/other/spacecraft" },
      }),
    ).toThrow();
    expect(() =>
      readConfiguration({
        ...snapshot,
        document: {
          ...snapshot.document,
          protocol: {
            downlink: "tm",
            uplink: "tc",
            frame_size: 10,
            secondary_header_length: 20,
            insert_zone_length: 0,
            ocf_length: 0,
            truncated_primary_header: false,
          },
        },
      }),
    ).toThrow();
  });
  it("uses native section links and saves a selected revision without activating it", async () => {
    const snapshot = configurationFixture(),
      drafts = createConfigurationDrafts();
    const save = vi
      .fn<ConfigurationPort["save"]>()
      .mockResolvedValue({ status: "ok", message: "Saved" });
    const port: ConfigurationPort = {
      save,
      activate: vi.fn().mockResolvedValue({ status: "ok", message: "Activated" }),
      decide: vi.fn().mockResolvedValue({ status: "ok", message: "Approved" }),
      review: vi.fn().mockResolvedValue({ status: "ok", message: "Saved" }),
      catalog: vi.fn().mockResolvedValue({ catalog_id: "catalog-1", packets: [] }),
    };
    const wrapper = mount(SpacecraftConfigurationPage, {
      attachTo: document.body,
      props: {
        data: snapshot,
        identity: { organizationId: "org-1", missionId: "mission-1", spacecraftId: "spacecraft-1" },
        port,
        drafts,
      },
    });
    try {
      expect(wrapper.find('nav[aria-label="Spacecraft sections"] a').attributes("href")).toBe(
        "/missions/mission-1/spacecraft/spacecraft-1?section=overview",
      );
      const session = drafts.receive(snapshot);
      session.draft = {
        ...session.draft,
        catalog_revision_id: "catalog-1",
        commanding_enabled: true,
      };
      await flushPromises();
      await wrapper.get("#spacecraft-save-draft").trigger("click");
      await flushPromises();
      expect(save).toHaveBeenCalledWith(snapshot.token, session.draft);
      expect(snapshot.active).toBeNull();
      expect(port.review).not.toHaveBeenCalled();
      const restored = drafts.receive(snapshot);
      expect(restored.draft.catalog_revision_id).toBe("catalog-1");
    } finally {
      wrapper.unmount();
    }
  });
  it("reports an interrupted write as unconfirmed and rejects packet responses for another revision", async () => {
    const failed = createConfigurationPort(async () => {
      throw new Error("disconnected");
    });
    expect((await failed.save("a".repeat(64), configurationFixture().document)).status).toBe(
      "unconfirmed",
    );
    const port = createConfigurationPort(async () => ({
      status: "ok",
      data: { catalog_id: "other", packets: [] },
    }));
    await expect(port.catalog("catalog-1")).rejects.toThrow();
  });
});
