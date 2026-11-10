import { ref, type Ref } from "vue";
import { describeApiError } from "@/api";
import { fetchLost, type ReviewKey, type ReviewSummary } from "./api.ts";
import { allLost, reviewCsv, reviewFileName } from "./export.ts";

/** K3 Export CSV: walk every lost-pass page, build the CSV client-side, hand the file over. */
export function useReviewExport(
  key: Readonly<Ref<ReviewKey>>,
  missionSlug: Readonly<Ref<string>>,
  summary: Readonly<Ref<ReviewSummary | null>>,
) {
  const busy = ref(false);
  const failure = ref<string | null>(null);

  async function run() {
    const s = summary.value;
    if (!s || busy.value) return;
    busy.value = true;
    failure.value = null;
    try {
      const controller = new AbortController();
      const lost = await allLost(key.value, (k) => fetchLost(k, controller.signal));
      if (!lost.ok) {
        failure.value = `The export didn't finish: ${describeApiError(lost.error)}`;
        return;
      }
      const blob = new Blob([reviewCsv(lost.value)], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = reviewFileName(missionSlug.value, key.value, s.from, s.to);
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      busy.value = false;
    }
  }

  return { busy, failure, run };
}
