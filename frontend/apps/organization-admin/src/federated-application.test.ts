import { describe, expect, it } from "vite-plus/test";
import { manifest } from "./federated-application";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";

describe("organization admin federated application", () => {
  it("publishes the complete distinct post-auth surface manifest", () => {
    expect(manifest.application.applicationKey).toBe("organization_admin");
    expect(manifest.package.trust).toBe("first_party");
    expect(manifest.surfaces).toHaveLength(12);
    expect(new Set(manifest.surfaces.map((surface) => surface.surfaceId)).size).toBe(12);
    expect(manifest.surfaces.map((surface) => surface.renderer.exposedModule)).toEqual(
      expect.arrayContaining([
        "./OrganizationHome",
        "./ProviderAccountListPage",
        "./ProviderAccountNew",
        "./ProviderAccountShow",
        "./NotificationsPage",
        "./NotificationsBell",
        "./AdminHome",
        "./AdminRuntime",
        "./AdminOrganizationListPage",
        "./AdminOrganizationNew",
        "./AdminOrganizationShow",
        "./AdminOrganizationInvite",
      ]),
    );
  });

  it("exports an application wrapper for host-selected surfaces", () => {
    expect(OrganizationAdminApplication).toBeDefined();
    expect(
      manifest.surfaces.find((surface) => surface.surfaceId === "notifications")?.actions,
    ).toEqual(["accept_invitation", "mark_notification_read"]);
  });
});
