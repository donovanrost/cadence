import "./env.d.ts"

import {mount} from "@vue/test-utils"
import {describe, expect, it, vi} from "vite-plus/test"
import SpacecraftApplication from "./SpacecraftApplication.vue"
import {manifest} from "./federated-application"

describe("Spacecraft federated application", () => {
  it("claims every Spacecraft page while preserving the Phoenix prop and event boundary", async () => {
    const wrapper = mount(SpacecraftApplication, {
      props: {
        component: "SpacecraftCommanding",
        pageProps: {
          page: {
            id: "spacecraft-commanding-page",
            title: "Commanding for Firebird",
            subtitle: "Server-owned commanding setup.",
            eyebrow: "Command Interpretation",
            breadcrumbs: [{label: "Firebird", href: null}],
            status: {tone: "info", label: "Not tracked"},
          },
          panels: [],
          readiness: {
            eyebrow: "Readiness Impact",
            title: "Not part of readiness",
            description: "Phoenix owns readiness.",
            status: {tone: "info", label: "Placeholder"},
          },
        },
      },
    })

    expect(wrapper.find("#spacecraft-remote-application").exists()).toBe(true)
    expect(wrapper.find("#spacecraft-commanding-page").exists()).toBe(true)
    wrapper.unmount()
  })

  it("keeps the first-party manifest identity and page surface contracts stable", () => {
    expect(manifest.application.applicationKey).toBe("spacecraft")
    expect(manifest.package.trust).toBe("first_party")
    expect(manifest.surfaces).toHaveLength(12)
    expect(manifest.surfaces.map((surface) => surface.surfaceId)).toContain("telemetry_decom")
    expect(manifest.surfaces.find((surface) => surface.surfaceId === "telemetry_decom")?.dataContract).toEqual({
      id: "cadence.telemetry_decom.manage",
      version: 1,
    })
  })

  it("forwards application lifecycle contributions to the Phoenix-owned caller", async () => {
    const install = vi.fn()
    const wrapper = mount(SpacecraftApplication, {
      props: {
        component: "SpacecraftApplications",
        pageProps: {
          profile: {
            kind: "pinned",
            id: "spacecraft-applications-profile",
            label: "Pinned Profile",
            display_name: "Firebird bus",
            version: 1,
            status: {tone: "ready", label: "Current"},
          },
          applications: [
            {
              id: "spacecraft-application-telemetry_decom",
              application_key: "telemetry_decom",
              application_version: 1,
              display_name: "Telemetry Decom",
              description: "Packet interpretation.",
              lifecycle_state: null,
              installable: true,
              manageable: false,
              uninstallable: false,
              scope_label: "Spacecraft application",
              manage_path: "#",
              status: {
                state: "available",
                label: "Available",
                tone: "info",
                facts: [],
              },
              install_action: {
                id: "install-spacecraft-application-telemetry_decom",
                action_id: "install_application",
                label: "Install",
                variant: "primary",
                effect: "persist",
                execution: "synchronous",
                confirmation: null,
              },
              disable_action: null,
              uninstall_action: null,
              unavailable_message: null,
            },
          ],
        },
        onInstall: install,
      },
    })

    await wrapper.find("#install-spacecraft-application-telemetry_decom").trigger("click")
    expect(install).toHaveBeenCalledWith({key: "telemetry_decom"})
    wrapper.unmount()
  })
})
