import { computed, ref, shallowRef, watch } from "vue";
import {
  readSettingsSnapshot,
  type SettingsContext,
  type SettingsSectionPort,
  type SettingsSnapshot,
} from "./settings-section";

type Draft<T> = Readonly<{
  token: string;
  value: T | null;
  allowOverride: boolean;
  baseline: T | null;
  baselineAllowOverride: boolean;
}>;
type SectionProps = {
  snapshot: unknown;
  context: SettingsContext;
  canEdit: boolean;
  port: SettingsSectionPort;
};
const equal = (one: unknown, two: unknown) => JSON.stringify(one) === JSON.stringify(two);
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);

/** Vue adapter for the SDK's scoped draft, concurrency, and write-result contract. */
export function useSettingsSection<T>(props: SectionProps, read: (value: unknown) => T) {
  const latest = computed(() => {
    const snapshot = readSettingsSnapshot(props.snapshot, read);
    if ((props.context.scope === "organization") !== (snapshot.source === "organization"))
      throw Error("Settings source does not match this scope.");
    return snapshot;
  });
  const fresh = (value: SettingsSnapshot<T>): Draft<T> => ({
    token: value.token,
    value: value.saved,
    allowOverride: value.allowOverride,
    baseline: value.saved,
    baselineAllowOverride: value.allowOverride,
  });
  function restore(): Draft<T> {
    const retained = props.port.restoreDraft();
    if (
      record(retained) &&
      typeof retained.token === "string" &&
      /^[a-f0-9]{64}$/.test(retained.token) &&
      typeof retained.allowOverride === "boolean" &&
      typeof retained.baselineAllowOverride === "boolean"
    ) {
      try {
        const restored = {
          token: retained.token,
          value: retained.value === null ? null : read(retained.value),
          baseline: retained.baseline === null ? null : read(retained.baseline),
          allowOverride: retained.allowOverride,
          baselineAllowOverride: retained.baselineAllowOverride,
        };
        if (
          props.context.scope === "organization" &&
          (restored.value === null || restored.baseline === null)
        )
          return fresh(latest.value);
        return equal(restored.value, latest.value.saved) &&
          (props.context.scope === "mission" ||
            restored.allowOverride === latest.value.allowOverride)
          ? fresh(latest.value)
          : restored;
      } catch {
        /* The owner cannot reuse a draft from an incompatible value contract. */
      }
    }
    return fresh(latest.value);
  }
  const draft = shallowRef(restore());
  const busy = ref(false);
  const uncertain = ref(false);
  const message = ref("");
  const dirty = computed(
    () =>
      !equal(draft.value.value, draft.value.baseline) ||
      (props.context.scope === "organization" &&
        draft.value.allowOverride !== draft.value.baselineAllowOverride),
  );
  const conflict = computed(() => dirty.value && draft.value.token !== latest.value.token);
  const editable = computed(
    () =>
      props.canEdit &&
      !busy.value &&
      !uncertain.value &&
      (props.context.scope === "organization" || latest.value.allowOverride),
  );
  const effective = computed(() =>
    props.context.scope === "mission" && !latest.value.allowOverride
      ? latest.value.organizationDefault
      : (draft.value.value ?? latest.value.organizationDefault),
  );
  const source = computed(() =>
    props.context.scope === "organization"
      ? "organization"
      : !latest.value.allowOverride
        ? "enforced"
        : draft.value.value === null
          ? "inherited"
          : "overridden",
  );
  watch(
    () => latest.value.token,
    () => {
      if (
        !dirty.value ||
        (equal(draft.value.value, latest.value.saved) &&
          (props.context.scope === "mission" ||
            draft.value.allowOverride === latest.value.allowOverride))
      )
        draft.value = fresh(latest.value);
    },
  );
  watch(draft, (value) => props.port.retainDraft(value, dirty.value), {
    immediate: true,
    flush: "sync",
  });
  function choose(value: T) {
    if (editable.value) draft.value = { ...draft.value, value };
  }
  function allowOverrides(value: boolean) {
    if (editable.value && props.context.scope === "organization")
      draft.value = { ...draft.value, allowOverride: value };
  }
  function reset() {
    if (editable.value && props.context.scope === "mission")
      draft.value = { ...draft.value, value: null };
  }
  function discard() {
    if (!busy.value) {
      draft.value = fresh(latest.value);
      message.value = "";
      uncertain.value = false;
    }
  }
  function keepChanges() {
    if (editable.value)
      draft.value = {
        ...draft.value,
        token: latest.value.token,
        baseline: latest.value.saved,
        baselineAllowOverride: latest.value.allowOverride,
      };
  }
  async function refresh() {
    busy.value = true;
    try {
      await props.port.refresh();
      uncertain.value = false;
      message.value = "Saved values refreshed. Review your changes before saving.";
    } catch {
      message.value = "Saved values are unavailable. Your draft is still here.";
    } finally {
      busy.value = false;
    }
  }
  async function save() {
    if (!editable.value || !dirty.value || conflict.value) return;
    busy.value = true;
    message.value = "";
    const current = draft.value;
    try {
      const document =
        props.context.scope === "organization"
          ? { value: current.value, allow_override: current.allowOverride }
          : { value: current.value };
      const result = await props.port.save(current.token, document);
      if (result.status === "saved") {
        draft.value = fresh(readSettingsSnapshot(result.snapshot, read));
        message.value = "Changes saved.";
      } else if (result.status === "rejected") message.value = result.message;
      else {
        uncertain.value = true;
        message.value =
          "The save could not be confirmed. Check the saved values before trying again.";
      }
    } catch {
      uncertain.value = true;
      message.value =
        "The save could not be confirmed. Check the saved values before trying again.";
    } finally {
      busy.value = false;
    }
  }
  return {
    latest,
    draft,
    dirty,
    conflict,
    busy,
    uncertain,
    editable,
    effective,
    source,
    message,
    choose,
    allowOverrides,
    reset,
    discard,
    keepChanges,
    refresh,
    save,
  };
}
