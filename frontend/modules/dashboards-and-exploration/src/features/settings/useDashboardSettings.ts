import { computed, onBeforeUnmount, onMounted, reactive, ref, shallowRef, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type {
  SettingsState,
  SettingsModel,
  SettingsAction,
  SettingsQuery,
  SettingsReceipt,
  Visibility,
} from "./contracts";
import { exact, readSettingsState, readSettingsReceipt } from "./validation";
import { parseRuntimeDefaults } from "../../shared/runtime-defaults";

const values = (m: SettingsModel) => ({
  name: m.name,
  description: m.description,
  tags: m.tags.join(", "),
  defaults_json: m.defaults_json,
});
const signature = (v: object) => JSON.stringify(v);
const sameQuery = (a: SettingsQuery, b: SettingsQuery) =>
  Object.keys(a).every((k) => a[k as keyof SettingsQuery] === b[k as keyof SettingsQuery]);
const bytes = (v: string) => new TextEncoder().encode(v).length;

export function useDashboardSettings(props: {
  state: SettingsState;
  context: OpsPageContext;
  port: OpsPagePort;
}) {
  const state = shallowRef(readSettingsState(props.state, props.context));
  const model = computed(() => state.value.model);
  const draft = reactive(values(model.value));
  const baseline = shallowRef({
    version: model.value.document_version,
    revision: model.value.revision,
    signature: signature(draft),
  });
  const pending = ref(false),
    review = ref(state.value.phase === "review"),
    notice = ref("");
  const sequence = ref(state.value.sequence);
  const lastReceipt = shallowRef<SettingsReceipt | null>(null);
  const share = reactive({
    data_visibility: "authorized_runtime_data" as Visibility,
    expires_in_hours: "" as string | number,
  });
  const snapshotVisibility = ref<Visibility>("definition_only");
  const dirty = computed(() => signature(draft) !== baseline.value.signature);
  const stale = computed(
    () =>
      baseline.value.version !== model.value.document_version ||
      baseline.value.revision !== model.value.revision,
  );
  const writable = computed(
    () => !pending.value && !review.value && model.value.lifecycle === "active",
  );
  const tags = () =>
    draft.tags
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);
  const validation = computed(() => {
    if (!draft.name.trim() || bytes(draft.name) > 120)
      return "Name is required and must fit within 120 bytes.";
    if (bytes(draft.description) > 500) return "Description must fit within 500 bytes.";
    const t = tags();
    if (t.length > 32 || new Set(t).size !== t.length || t.some((v) => bytes(v) > 64))
      return "Use up to 32 unique tags, each at most 64 bytes.";
    try {
      parseRuntimeDefaults(draft.defaults_json);
    } catch (e) {
      return (e as Error).message;
    }
    return "";
  });
  const canSave = computed(
    () => writable.value && !stale.value && dirty.value && !validation.value,
  );
  const validExpiration = computed(
    () =>
      share.expires_in_hours === "" ||
      (/^\d+$/.test(String(share.expires_in_hours)) &&
        Number(share.expires_in_hours) >= 1 &&
        Number(share.expires_in_hours) <= 8760),
  );
  const base = computed(
    () =>
      "/missions/" +
      encodeURIComponent(model.value.mission_id) +
      "/ops/dashboards/" +
      encodeURIComponent(model.value.dashboard_id),
  );
  const missionBase = computed(
    () => "/missions/" + encodeURIComponent(model.value.mission_id) + "/ops",
  );

  function resetDraft() {
    Object.assign(draft, values(model.value));
    baseline.value = {
      version: model.value.document_version,
      revision: model.value.revision,
      signature: signature(draft),
    };
  }
  function adopt(next: SettingsState, unlock = false) {
    const wasDirty = dirty.value;
    state.value = next;
    sequence.value = next.sequence;
    if (!wasDirty) resetDraft();
    if (unlock) review.value = next.phase === "review";
    else if (next.phase === "review") review.value = true;
  }
  watch(
    () => props.state,
    (next) => {
      if (pending.value) return;
      const admitted = readSettingsState(next, props.context);
      if (admitted.sequence >= sequence.value) adopt(admitted);
    },
  );

  let disposed = false,
    disposeGuard: (() => void) | undefined;
  const canLeave = () =>
    !pending.value &&
    (!dirty.value || window.confirm("Leave without saving your dashboard metadata edits?"));
  const beforeUnload = (e: BeforeUnloadEvent) => {
    if (pending.value || dirty.value) {
      e.preventDefault();
      e.returnValue = "";
    }
  };
  onMounted(() => {
    disposeGuard = props.port.guardNavigation?.(canLeave);
    window.addEventListener("beforeunload", beforeUnload);
  });
  onBeforeUnmount(() => {
    disposed = true;
    disposeGuard?.();
    window.removeEventListener("beforeunload", beforeUnload);
  });

  function discard() {
    if (
      !pending.value &&
      (!dirty.value ||
        window.confirm("Discard your local metadata edits and use the loaded settings?"))
    )
      resetDraft();
  }
  function rebase() {
    if (pending.value || review.value || !stale.value) return;
    if (
      !window.confirm(
        "Use loaded draft v" +
          model.value.document_version +
          " for your local edits? Saving will replace its metadata and defaults with your form values.",
      )
    )
      return;
    baseline.value = {
      version: model.value.document_version,
      revision: model.value.revision,
      signature: signature(values(model.value)),
    };
  }
  function navigate(event: MouseEvent, href: string) {
    if (pending.value) {
      event.preventDefault();
      return;
    }
    if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey)
      return;
    event.preventDefault();
    props.port.navigate(href);
  }
  function exportDashboard(event: MouseEvent) {
    if (
      !writable.value ||
      (dirty.value &&
        !window.confirm(
          "Export the latest saved draft? Your unsaved metadata edits are not included.",
        ))
    )
      event.preventDefault();
  }
  function command(action: SettingsAction, shareId?: string): Record<string, unknown> {
    const observed = {
      expected_version: model.value.document_version,
      expected_revision: model.value.revision,
    };
    if (action === "reload_settings") return {};
    if (action === "save_settings")
      return {
        ...observed,
        name: draft.name,
        description: draft.description,
        tags: tags(),
        defaults_json: draft.defaults_json,
      };
    if (action === "create_share")
      return {
        ...observed,
        data_visibility: share.data_visibility,
        expires_in_hours: share.expires_in_hours === "" ? null : Number(share.expires_in_hours),
      };
    if (action === "create_snapshot")
      return { ...observed, data_visibility: snapshotVisibility.value };
    if (action === "revoke_share") return { ...observed, share_id: shareId };
    return observed;
  }

  async function execute(action: Exclude<SettingsAction, "page_settings">, shareId?: string) {
    if (pending.value || (action !== "reload_settings" && !writable.value)) return;
    if (action === "save_settings" && !canSave.value) return;
    if (action === "create_share" && !validExpiration.value) return;
    if (
      action === "revoke_share" &&
      !model.value.shares.rows.some((s) => s.id === shareId && s.state !== "revoked")
    )
      return;
    if (
      action === "archive_dashboard" &&
      !window.confirm(
        "Archive " +
          model.value.name +
          "? It will leave active dashboard lists. Saved versions remain; unsaved metadata is not saved.",
      )
    )
      return;
    if (
      action === "create_snapshot" &&
      !window.confirm(
        "Capture saved draft v" +
          model.value.document_version +
          "? This preserves its definition, not telemetry values or unsaved edits.",
      )
    )
      return;
    if (
      action === "revoke_share" &&
      !window.confirm("Revoke this mission share? Existing links will stop working.")
    )
      return;
    const observed = model.value;
    const requested = sequence.value + 1;
    const fields = command(action, shareId);
    sequence.value = requested;
    pending.value = true;
    review.value = true;
    notice.value = "";
    try {
      const response = exact(
        await props.port.execute(action, { sequence: requested, command: fields }),
        ["status", "receipt", "state"],
      );
      if (disposed) return;
      const next = readSettingsState(response.state, props.context);
      // A rejected command may not have consumed its sequence. Recover only from
      // a valid server state, and never unlock writes except through explicit reload.
      if (
        response.status === "rejected" &&
        next.sequence === requested - 1 &&
        response.receipt === null
      ) {
        sequence.value = next.sequence;
        throw Error("Rejected before admission");
      }
      if (next.sequence !== requested) throw Error("Unconfirmed sequence");
      sequence.value = next.sequence;
      if (action !== "reload_settings" && !sameQuery(next.model.query, observed.query))
        throw Error("Changed page");
      if (response.status === "invalid" && response.receipt === null && next.phase === "ready") {
        adopt(next, true);
        notice.value =
          "The change failed validation. Check your fields and runtime defaults; no change was applied.";
        return;
      }
      if (response.status !== "ok") throw Error("Unconfirmed outcome");
      if (action === "reload_settings") {
        if (response.receipt !== null || next.phase !== "ready") throw Error("Unconfirmed reload");
        adopt(next, true);
        notice.value =
          dirty.value && stale.value
            ? "Newer settings were loaded. Review them before using that revision for your local edits."
            : "Settings reloaded. Local edits have been retained.";
        return;
      }
      const receipt = readSettingsReceipt(response.receipt, observed, action);
      if (next.phase !== "review" || (action === "revoke_share" && receipt.resource_id !== shareId))
        throw Error("Unconfirmed receipt");
      lastReceipt.value = receipt;
      adopt(next);
      if (action === "save_settings")
        baseline.value = {
          version: receipt.document_version,
          revision: receipt.revision,
          signature: signature(draft),
        };
      notice.value =
        action === "save_settings"
          ? "Saved as draft v" + receipt.document_version + ". Publication is unchanged."
          : action === "create_share"
            ? "Share created: " + receipt.resource_id
            : action === "create_snapshot"
              ? "Snapshot created: " + receipt.resource_id
              : action === "revoke_share"
                ? "Share revoked."
                : "Dashboard archived. Saved versions remain.";
      notice.value += " Reload settings before another change.";
    } catch {
      if (!disposed)
        notice.value =
          "The outcome could not be confirmed. Reload settings and review the current state before another change.";
    } finally {
      if (!disposed) pending.value = false;
    }
  }

  async function page(key: keyof SettingsQuery, cursor: string | null) {
    if (pending.value) return;
    const query = { ...model.value.query, [key]: cursor };
    const expectedSequence = sequence.value;
    pending.value = true;
    try {
      const response = exact(await props.port.execute("page_settings", query), [
        "status",
        "receipt",
        "state",
      ]);
      if (disposed) return;
      const next = readSettingsState(response.state, props.context);
      if (
        response.status !== "ok" ||
        response.receipt !== null ||
        next.sequence !== expectedSequence ||
        !sameQuery(next.model.query, query)
      )
        throw Error("Unconfirmed page");
      adopt(next);
    } catch {
      if (!disposed)
        notice.value =
          "This metadata page could not be loaded. Your local edits have been retained.";
    } finally {
      if (!disposed) pending.value = false;
    }
  }

  return {
    model,
    draft,
    share,
    snapshotVisibility,
    pending,
    review,
    dirty,
    stale,
    writable,
    canSave,
    validation,
    validExpiration,
    notice,
    lastReceipt,
    base,
    missionBase,
    execute,
    page,
    discard,
    rebase,
    navigate,
    exportDashboard,
  };
}
