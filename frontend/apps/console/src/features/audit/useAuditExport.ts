import { ref, type Ref } from "vue";
import { describeApiError } from "@/api";
import { fetchAudit, type AuditQuery } from "./api.ts";
import { allEvents, auditCsv, auditFileName, exportCap, unreadNote } from "./export.ts";

/** Audit Export CSV: walk the filter's pages, build the CSV client-side, hand the file over. */
export function useAuditExport(
  query: Readonly<Ref<AuditQuery | null>>,
  orgSlug: Readonly<Ref<string>>,
) {
  const busy = ref(false);
  const note = ref<Readonly<{ tone: "caution" | "info"; text: string }> | null>(null);

  async function run() {
    const q = query.value;
    if (!q || busy.value) return;
    busy.value = true;
    note.value = null;
    try {
      const signal = new AbortController().signal;
      const r = await allEvents(q, (page) => fetchAudit(page, signal));
      if (!r.ok)
        return void (note.value = {
          tone: "caution",
          text: `The export didn't finish: ${describeApiError(r.error)}`,
        });
      const blob = new Blob([auditCsv(r.value.events)], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = auditFileName(orgSlug.value, q);
      a.click();
      URL.revokeObjectURL(url);
      const parts = [
        r.value.capped
          ? `Exported the first ${exportCap.toLocaleString("en-US")} events. Narrow the range or filters for the rest.`
          : null,
        // ux U86: never a silent short file.
        r.value.unshown > 0 ? unreadNote(r.value.unshown) : null,
      ].filter((p): p is string => p !== null);
      if (parts.length)
        note.value = { tone: r.value.unshown > 0 ? "caution" : "info", text: parts.join(" ") };
    } finally {
      busy.value = false;
    }
  }

  return { busy, note, run };
}

export type AuditExport = ReturnType<typeof useAuditExport>;
