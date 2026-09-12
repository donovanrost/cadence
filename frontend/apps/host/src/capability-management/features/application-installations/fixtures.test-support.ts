import type {
  ApplicationCard,
  InstallationSnapshot,
  LifecycleEvent,
  MissionPresentation,
  SpacecraftPresentation,
} from "./contracts";

const element = () => ({ attrs: {} });
const label = (text: string) => ({ attrs: {}, text });
const missionPath = "/missions/mission-a";
export function applicationFixture(key = "limits"): ApplicationCard {
  const action = (event: LifecycleEvent) => ({
    id: key + "-" + event,
    action_id: event,
    label: event,
    variant: event === "uninstall" ? ("danger" as const) : ("secondary" as const),
    effect: "durable",
    execution: "immediate",
    confirmation:
      event === "install"
        ? null
        : {
            title: "Change workspace access?",
            message: "Runtime state is retained.",
            confirm_label: event,
            tone: "attention" as const,
            prompt: "Keep runtime state and change workspace access?",
          },
  });
  return {
    id: "application-" + key,
    application_key: key,
    application_version: 1,
    display_name: key,
    description: "Optional application workspace",
    lifecycle_state: "installed",
    installable: true,
    manageable: true,
    uninstallable: true,
    scope_label: "Mission Application",
    manage_path: missionPath + "/applications/" + key,
    status: {
      state: "installed",
      label: "Installed",
      tone: "ready",
      facts: [{ id: "version", label: "Version", value: "1" }],
    },
    install_action: action("install"),
    disable_action: action("disable"),
    uninstall_action: action("uninstall"),
    unavailable_message: null,
  };
}
function header() {
  return {
    attrs: {},
    body: element(),
    content: element(),
    breadcrumbs: {
      attrs: {},
      items: [
        { label: "Mission", href: missionPath },
        { label: "Applications", href: null },
      ],
    },
    title: label("Applications"),
    subtitle: label("Manage optional application workspaces."),
  };
}
export function missionInstallationsFixture(): MissionPresentation {
  return {
    root: { attrs: { id: "mission-applications-page", class: "space-y-6" } },
    header: header(),
    applications_component: {
      attrs: { id: "mission-applications-component" },
      props: { applications: [applicationFixture()] },
    },
  };
}
export function spacecraftInstallationsFixture(): SpacecraftPresentation {
  const path = missionPath + "/spacecraft/spacecraft-a";
  return {
    root: { attrs: { id: "spacecraft-applications-page", class: "space-y-6" } },
    header: {
      ...header(),
      actions: {
        attrs: {},
        readiness: { attrs: { href: path + "/readiness" }, text: "Readiness" },
      },
    },
    component: { attrs: { id: "spacecraft-applications-component" } },
    profile: {
      kind: "pinned",
      id: "pinned-profile",
      label: "Pinned Profile",
      display_name: "Flight",
      version: 2,
      status: { tone: "ready", label: "Current" },
    },
    applications: [applicationFixture("telemetry_decom")],
  };
}
export function installationSnapshot(
  scope: "mission" | "spacecraft" = "mission",
): InstallationSnapshot {
  return scope === "mission"
    ? { version: 1, scope, status: "ready", data: missionInstallationsFixture() }
    : { version: 1, scope, status: "ready", data: spacecraftInstallationsFixture() };
}
