import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type {
  DashboardRow,
  DirectoryAction,
  DirectoryCommands,
  DirectoryFilters,
  DirectoryOutcome,
  DirectoryPage,
} from "./contracts";
import { dashboardHref, directoryHref } from "./href";
import { readOutcome } from "./validation";

export type DirectoryProps = {
  page: DirectoryPage;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
};
export type Notice = {
  tone: "info" | "warning";
  text: string;
  action?: { label: string; run: () => void };
};

const searchDelayMs = 250;
const highlightMs = 4000;

function failure(outcome: DirectoryOutcome): string | null {
  switch (outcome.status) {
    case "ok":
      return null;
    case "invalid":
      return "Enter a name of 1–512 characters.";
    case "forbidden":
      return "You can't change dashboards in this mission.";
    case "rejected":
    case "unknown":
      return "The change could not be confirmed. Reload the page before trying again.";
  }
}

/**
 * Owns the adopted directory page, URL filter navigation and sequenced actions.
 * Rows that change without an action of ours (someone else's save, live) are
 * highlighted briefly so the person notices them.
 */
export function useDashboardDirectory(props: DirectoryProps) {
  const page = shallowRef(props.page);
  const pending = ref(false);
  const notice = ref<Notice | null>(null);
  const highlighted = ref<string[]>([]);
  const query = ref(props.page.model.filters.query);
  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  let highlightTimer: ReturnType<typeof setTimeout> | undefined;
  let disposed = false;

  const model = computed(() => page.value.model);
  const mission = computed(() => props.context.missionId);
  const filtered = computed(() => {
    const f = model.value.filters;
    return f.query !== "" || f.tags.length > 0 || f.starred;
  });

  function adopt(next: DirectoryPage, live: boolean) {
    if (disposed || next.sequence < page.value.sequence) return;
    // Only someone else's change to the same view is news; a new filter is not.
    const sameView =
      JSON.stringify(page.value.model.filters) === JSON.stringify(next.model.filters);
    if (live && sameView) highlight(changedRows(page.value.model.rows, next.model.rows));
    page.value = next;
    if (searchTimer === undefined) query.value = next.model.filters.query;
  }
  watch(
    () => props.page,
    (next) => adopt(next, !pending.value),
  );

  function highlight(ids: string[]) {
    if (ids.length === 0) return;
    clearTimeout(highlightTimer);
    highlighted.value = ids;
    highlightTimer = setTimeout(() => (highlighted.value = []), highlightMs);
  }

  function navigate(href: string) {
    try {
      props.port.navigate(href);
    } catch {
      notice.value = { tone: "warning", text: "Navigation is unavailable. Reload the page." };
    }
  }

  const filter = (changes: Partial<Omit<DirectoryFilters, "page">>, page = 1) =>
    navigate(directoryHref(mission.value, { ...model.value.filters, ...changes }, page));

  const filters = {
    search(value: string) {
      query.value = value;
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => {
        searchTimer = undefined;
        filter({ query: value });
      }, searchDelayMs);
    },
    toggleTag(tag: string) {
      const tags = model.value.filters.tags;
      filter({ tags: tags.includes(tag) ? tags.filter((t) => t !== tag) : [...tags, tag] });
    },
    starredOnly: (starred: boolean) => filter({ starred }),
    showArchived: (archived: boolean) => filter({ archived }),
    sort: (sort: DirectoryFilters["sort"]) => filter({ sort }),
    page: (number: number) => filter({}, number),
    clear: () => filter({ query: "", tags: [], starred: false }),
  };

  async function execute<A extends DirectoryAction>(action: A, command: DirectoryCommands[A]) {
    if (disposed || pending.value) return null;
    pending.value = true;
    notice.value = null;
    try {
      const sequence = page.value.sequence + 1;
      const outcome = readOutcome(
        await props.port.execute(action, { sequence, command }),
        props.context,
      );
      if (outcome.page) adopt(outcome.page, false);
      const text = failure(outcome);
      if (text) notice.value = { tone: "warning", text };
      return outcome.status === "ok" ? outcome : null;
    } catch {
      notice.value = {
        tone: "warning",
        text: "The change could not be confirmed. Reload the page before trying again.",
      };
      return null;
    } finally {
      pending.value = false;
    }
  }

  const actions = {
    star: (row: DashboardRow) => execute("star", { dashboard_id: row.id, starred: !row.starred }),
    async archive(row: DashboardRow) {
      if (!(await execute("archive", { dashboard_id: row.id }))) return;
      notice.value = {
        tone: "info",
        text: `Archived “${row.name}”.`,
        action: { label: "Undo", run: () => void actions.restore(row) },
      };
    },
    async restore(row: DashboardRow) {
      if (await execute("restore", { dashboard_id: row.id })) {
        notice.value = { tone: "info", text: `Restored “${row.name}”.` };
        highlight([row.id]);
      }
    },
    async duplicate(row: DashboardRow, name: string) {
      const outcome = await execute("duplicate", { dashboard_id: row.id, name });
      if (!outcome) return;
      const id = outcome.result.dashboard_id;
      highlight([id]);
      notice.value = {
        tone: "info",
        text: `Created “${name}”.`,
        action: { label: "Open", run: () => navigate(dashboardHref(mission.value, id)) },
      };
    },
    dismiss: () => (notice.value = null),
  };

  onBeforeUnmount(() => {
    disposed = true;
    clearTimeout(searchTimer);
    clearTimeout(highlightTimer);
  });

  return { page, model, mission, filtered, pending, notice, highlighted, query, filters, actions };
}

/** Rows that are new, or whose name, description, tags or last save changed. */
function changedRows(before: DashboardRow[], after: DashboardRow[]): string[] {
  const previous = new Map(before.map((row) => [row.id, row]));
  return after
    .filter((row) => {
      const old = previous.get(row.id);
      return (
        !old ||
        old.name !== row.name ||
        old.description !== row.description ||
        old.updated_at !== row.updated_at ||
        old.tags.join() !== row.tags.join()
      );
    })
    .map((row) => row.id);
}

export type DashboardDirectory = ReturnType<typeof useDashboardDirectory>;
