import { computed, reactive, ref } from "vue";
import {
  configured,
  configurationChanges,
  emptyConfiguration,
  fleet,
  setupIssues,
  type Configuration,
  type Inspector,
  type RevisionId,
  type Scenario,
  type Section,
  type SpacecraftId,
} from "./fixtures";

type Review = Readonly<{ status: "submitted" | "approved"; configuration: Configuration }>;
type Activation = Readonly<{ number: number; catalog: RevisionId | null; label: string }>;
export type SpacecraftState = {
  active: Configuration | null;
  saved: Configuration;
  draft: Configuration;
  review: Review | null;
  history: readonly Activation[];
};

function spacecraftState(active: Configuration | null): SpacecraftState {
  return {
    active,
    saved: { ...(active ?? emptyConfiguration) },
    draft: { ...(active ?? emptyConfiguration) },
    review: null,
    history: active
      ? [
          {
            number: 1,
            catalog: active.catalog,
            label: `${active.catalog === "3.4" ? "12 Sep" : "28 Aug"} · Mission engineering`,
          },
        ]
      : [],
  };
}

export function useSpacecraftStudy(initial: Scenario) {
  const spacecraft = reactive<Record<SpacecraftId, SpacecraftState>>({
    "KESTREL-01": spacecraftState(configured("3.4")),
    "KESTREL-02": spacecraftState(configured("3.3")),
    "KESTREL-03": spacecraftState(null),
  });
  const selectedId = ref<SpacecraftId>(initial === "new" ? "KESTREL-03" : "KESTREL-02");
  const section = ref<Section>(
    initial === "review" || initial === "missing-input"
      ? "changes"
      : initial === "upgrade"
        ? "catalog"
        : "overview",
  );
  const inspector = ref<Inspector | null>(initial === "upgrade" ? "catalog" : null);
  const feedback = ref("");
  if (initial === "review" || initial === "missing-input") {
    const current = spacecraft["KESTREL-02"];
    current.draft = {
      ...current.draft,
      catalog: "3.4",
      ...(initial === "missing-input" ? { telemetryInput: null } : {}),
    };
    current.saved = { ...current.draft };
  }
  const current = computed(() => spacecraft[selectedId.value]);
  const identity = computed(() => fleet.find((craft) => craft.id === selectedId.value));
  const draft = computed(() => current.value.draft);
  const changes = computed(() => configurationChanges(current.value.active, draft.value));
  const unsaved = computed(() => configurationChanges(current.value.saved, draft.value).length > 0);
  const issues = computed(() => setupIssues(draft.value));
  const canReview = computed(
    () =>
      !unsaved.value &&
      changes.value.length > 0 &&
      issues.value.length === 0 &&
      !current.value.review,
  );
  const canActivate = computed(
    () =>
      current.value.review?.status === "approved" && !unsaved.value && issues.value.length === 0,
  );
  const canOpenOps = computed(() =>
    Boolean(current.value.active?.commandingEnabled && current.value.active.catalog),
  );

  function selectSpacecraft(id: SpacecraftId) {
    selectedId.value = id;
    inspector.value = null;
    feedback.value = "";
    if (section.value === "ops" && !canOpenOps.value) section.value = "overview";
  }
  function navigate(next: Section) {
    if (next === "ops" && !canOpenOps.value) return;
    section.value = next;
    inspector.value = null;
  }
  function edit(patch: Partial<Configuration>) {
    const next = { ...draft.value, ...patch };
    if (!configurationChanges(draft.value, next).length) return;
    const invalidated = Boolean(current.value.review);
    current.value.draft = next;
    current.value.review = null;
    feedback.value = invalidated ? "Configuration changed. Save and submit a new review." : "";
  }
  function saveDraft() {
    current.value.saved = { ...draft.value };
    feedback.value = `Draft saved for ${selectedId.value}. Active configuration is unchanged.`;
  }
  function discardUnsaved() {
    current.value.draft = { ...current.value.saved };
    feedback.value = "Unsaved edits discarded.";
  }
  function submitReview() {
    if (!canReview.value) return;
    current.value.review = { status: "submitted", configuration: { ...current.value.saved } };
    feedback.value = "Submitted for review.";
  }
  function simulateApproval() {
    const review = current.value.review;
    if (review?.status !== "submitted") return;
    current.value.review = { ...review, status: "approved" };
    feedback.value = "Approval received in the simulation. Ready to activate.";
  }
  function activate() {
    const review = current.value.review;
    if (!canActivate.value || review?.status !== "approved") return;
    current.value.active = { ...review.configuration };
    current.value.history = [
      {
        number: current.value.history.length + 1,
        catalog: review.configuration.catalog,
        label: "Just now · You · simulated",
      },
      ...current.value.history,
    ];
    current.value.review = null;
    feedback.value = `Configuration activated for ${selectedId.value}. Other spacecraft are unchanged.`;
  }
  function applyPreset() {
    edit({ downlink: "TM", uplink: "TC" });
    feedback.value = "Kestrel bus settings copied into this spacecraft's draft.";
  }
  return {
    spacecraft,
    selectedId,
    section,
    inspector,
    feedback,
    current,
    identity,
    draft,
    changes,
    unsaved,
    issues,
    canReview,
    canActivate,
    canOpenOps,
    selectSpacecraft,
    navigate,
    edit,
    saveDraft,
    discardUnsaved,
    submitReview,
    simulateApproval,
    activate,
    applyPreset,
  };
}
