import { computed, reactive, ref } from "vue";
import {
  actors,
  effectiveApproval,
  scopeNames,
  type ActorId,
  type ApprovalMode,
  type MissionId,
  type OrganizationPolicy,
  type Override,
  type Scenario,
  type ScopeKey,
  type SectionId,
  type ShelfMode,
} from "./fixtures";

function draft<T>(value: T) {
  return { saved: structuredClone(value), value: structuredClone(value), revision: 1 };
}
type Activation =
  | { status: "ready" }
  | { status: "pending"; requester: ActorId; basis: string }
  | { status: "active"; executor: ActorId; approval: ApprovalMode }
  | { status: "stale" }
  | { status: "rejected"; reviewer: ActorId; reason: string };

export function useSettingsStudy(initial: Scenario) {
  const scope = ref<ScopeKey>(initial === "organization" ? "organization" : "kestrel");
  const section = ref<SectionId>(
    initial === "application-unavailable" ? "commanding.defaults" : "cadence.governance",
  );
  const destination = ref<"settings" | "activation" | "outside">("settings");
  const outsideTitle = ref("Cadence");
  const actor = ref<ActorId>("maya");
  const search = ref("");
  const notice = ref("");
  const rationale = ref("");
  const canEdit = initial !== "read-only";
  const applicationAvailable = ref(initial !== "application-unavailable");
  const organization = reactive(
    draft<OrganizationPolicy>({
      approval:
        initial === "single-operator" || initial === "organization" ? "direct" : "independent",
      allowOverrides: initial !== "enforced",
    }),
  );
  const missionPolicies = reactive({
    kestrel: draft<Override<ApprovalMode>>(
      initial === "overridden" ? { mode: "override", value: "direct" } : { mode: "inherit" },
    ),
    pathfinder: draft<Override<ApprovalMode>>({ mode: "override", value: "direct" }),
  });
  const organizationShelf = reactive(draft<ShelfMode>("expanded"));
  const missionShelves = reactive({
    kestrel: draft<Override<ShelfMode>>({ mode: "inherit" }),
    pathfinder: draft<Override<ShelfMode>>({ mode: "inherit" }),
  });
  const activations = reactive<Record<MissionId, Activation>>({
    kestrel: { status: "ready" },
    pathfinder: { status: "ready" },
  });
  const activity = ref<readonly { id: number; scope: string; section: string; actor: string }[]>(
    [],
  );
  const activeMission = computed<MissionId>(() =>
    scope.value === "organization" ? "kestrel" : scope.value,
  );
  const source = computed(() => {
    if (scope.value === "organization") return "organization";
    if (section.value === "cadence.governance")
      return effectiveApproval(organization.saved, missionPolicies[scope.value].value).source;
    return missionShelves[scope.value].value.mode === "inherit" ? "inherited" : "overridden";
  });
  const approval = computed(() =>
    scope.value === "organization"
      ? organization.value.approval
      : effectiveApproval(organization.saved, missionPolicies[scope.value].value).value,
  );
  const shelf = computed(() => {
    if (scope.value === "organization") return organizationShelf.value;
    const override = missionShelves[scope.value].value;
    return override.mode === "inherit" ? organizationShelf.saved : override.value;
  });
  const editable = computed(
    () =>
      canEdit &&
      source.value !== "enforced" &&
      (section.value !== "commanding.defaults" || applicationAvailable.value),
  );
  const dirty = computed(() => sectionDirty(scope.value, section.value));
  const currentActivation = computed(() => activations[activeMission.value]);
  const savedApproval = computed(
    () => effectiveApproval(organization.saved, missionPolicies[activeMission.value].saved).value,
  );

  function sectionDirty(key: ScopeKey, id: SectionId) {
    const value =
      id === "cadence.governance"
        ? key === "organization"
          ? organization
          : missionPolicies[key]
        : key === "organization"
          ? organizationShelf
          : missionShelves[key];
    return JSON.stringify(value.value) !== JSON.stringify(value.saved);
  }
  function chooseApproval(value: ApprovalMode) {
    if (!editable.value) return;
    if (scope.value === "organization") {
      organization.value.approval = value;
      if (value === "direct") organization.value.allowOverrides = true;
    } else missionPolicies[scope.value].value = { mode: "override", value };
    notice.value = "";
  }
  function allowOverrides(value: boolean) {
    if (canEdit && scope.value === "organization" && organization.value.approval === "independent")
      organization.value.allowOverrides = value;
  }
  function chooseShelf(value: ShelfMode) {
    if (!editable.value) return;
    if (scope.value === "organization") organizationShelf.value = value;
    else missionShelves[scope.value].value = { mode: "override", value };
    notice.value = "";
  }
  function resetToOrganization() {
    if (!editable.value || scope.value === "organization") return;
    if (section.value === "cadence.governance")
      missionPolicies[scope.value].value = { mode: "inherit" };
    else missionShelves[scope.value].value = { mode: "inherit" };
  }
  function save() {
    if (!editable.value || !dirty.value) return;
    const key = scope.value;
    if (section.value === "cadence.governance") {
      if (key === "organization") {
        organization.saved = { ...organization.value };
        organization.revision += 1;
      } else {
        missionPolicies[key].saved = { ...missionPolicies[key].value };
        missionPolicies[key].revision += 1;
      }
      for (const mission of ["kestrel", "pathfinder"] as const) {
        if (
          (key === "organization" || key === mission) &&
          activations[mission].status === "pending"
        )
          activations[mission] = { status: "stale" };
      }
    } else if (key === "organization") {
      organizationShelf.saved = organizationShelf.value;
      organizationShelf.revision += 1;
    } else {
      missionShelves[key].saved = { ...missionShelves[key].value };
      missionShelves[key].revision += 1;
    }
    activity.value = [
      {
        id: activity.value.length + 1,
        scope: scopeNames[key],
        section:
          section.value === "cadence.governance" ? "Approval requirement" : "Command shelf default",
        actor: actors[actor.value],
      },
      ...activity.value,
    ];
    notice.value = `Saved ${section.value === "cadence.governance" ? "governance" : "commanding"} settings for ${scopeNames[key]}.`;
  }
  function discard() {
    const key = scope.value;
    if (section.value === "cadence.governance") {
      if (key === "organization") organization.value = { ...organization.saved };
      else missionPolicies[key].value = { ...missionPolicies[key].saved };
    } else if (key === "organization") organizationShelf.value = organizationShelf.saved;
    else missionShelves[key].value = { ...missionShelves[key].saved };
    notice.value = "Unsaved changes discarded.";
  }
  function impact(mission: MissionId) {
    return effectiveApproval(
      scope.value === "organization" ? organization.value : organization.saved,
      missionPolicies[mission].saved,
    );
  }
  function basis() {
    return `${organization.revision}:${missionPolicies[activeMission.value].revision}`;
  }
  function activateOrSubmit() {
    if (currentActivation.value.status === "active" || currentActivation.value.status === "pending")
      return;
    activations[activeMission.value] =
      savedApproval.value === "direct"
        ? { status: "active", executor: actor.value, approval: "direct" }
        : { status: "pending", requester: actor.value, basis: basis() };
    rationale.value = "";
  }
  function decide(approved: boolean) {
    const request = currentActivation.value;
    if (
      request.status !== "pending" ||
      request.requester === actor.value ||
      !rationale.value.trim()
    )
      return;
    if (request.basis !== basis()) {
      activations[activeMission.value] = { status: "stale" };
      return;
    }
    activations[activeMission.value] = approved
      ? { status: "active", executor: actor.value, approval: "independent" }
      : { status: "rejected", reviewer: actor.value, reason: rationale.value.trim() };
  }
  return {
    scope,
    section,
    destination,
    outsideTitle,
    actor,
    search,
    notice,
    rationale,
    canEdit,
    applicationAvailable,
    organization,
    missionPolicies,
    organizationShelf,
    source,
    approval,
    shelf,
    editable,
    dirty,
    activeMission,
    currentActivation,
    savedApproval,
    activity,
    sectionDirty,
    chooseApproval,
    allowOverrides,
    chooseShelf,
    resetToOrganization,
    save,
    discard,
    impact,
    activateOrSubmit,
    decide,
  };
}
export type SettingsStudy = ReturnType<typeof useSettingsStudy>;
