import { computed, reactive, ref } from "vue";
import {
  NOW,
  dashboardPath,
  dashboardsFor,
  teammateDashboard,
  type Scenario,
  type StudyDashboard,
} from "./fixtures";

/** Where personal shortcuts (starred, recently viewed) sit above the list. */
export type QuickAccess =
  | "none"
  | "links"
  | "panels"
  | "refined"
  | "tabbed"
  | "rail"
  | "tiles"
  | "resume";
/** How the results render; the list is the chosen direction. */
export type Presentation = "list" | "table";
export type Sort = "updated" | "name-asc" | "name-desc";
export const sortLabels: Record<Sort, string> = {
  updated: "Recently updated",
  "name-asc": "Name A–Z",
  "name-desc": "Name Z–A",
};
export type Notice = { text: string; action?: { label: string; run: () => void } };
export type DirectoryStudy = ReturnType<typeof useDirectoryStudy>;

const pageSize = 50;
const you = "Mission engineer";

// In-memory model of the proposed directory. Production keeps filters in the
// URL and resolves them on the server; the study only simulates the outcome.
export function useDirectoryStudy(scenario: Scenario) {
  const dashboards = ref<StudyDashboard[]>(dashboardsFor(scenario));
  const author = scenario !== "viewer";
  const filters = reactive({
    query: "",
    tags: [] as string[],
    starred: false,
    archived: scenario === "archived",
    sort: "updated" as Sort,
    page: 1,
  });
  const notice = ref<Notice | null>(null);
  const highlighted = ref<string[]>([]);

  const active = computed(() => dashboards.value.filter((item) => !item.archived));
  const tags = computed(() => [...new Set(dashboards.value.flatMap((item) => item.tags))].sort());
  const filtered = computed(
    () => filters.query !== "" || filters.tags.length > 0 || filters.starred,
  );
  const matches = computed(() => dashboards.value.filter(matching).sort(order(filters.sort)));
  const pages = computed(() => Math.max(1, Math.ceil(matches.value.length / pageSize)));
  const rows = computed(() =>
    matches.value.slice((filters.page - 1) * pageSize, filters.page * pageSize),
  );
  const range = computed(() => {
    const start = (filters.page - 1) * pageSize;
    return `${start + 1}–${start + rows.value.length} of ${matches.value.length}`;
  });
  const starred = computed(() => active.value.filter((item) => item.starred));
  const recent = computed(() =>
    active.value
      .filter((item) => item.lastViewedAt !== null)
      .sort((a, b) => (b.lastViewedAt ?? 0) - (a.lastViewedAt ?? 0))
      .slice(0, 5),
  );

  function matching(item: StudyDashboard) {
    const haystack = [item.name, item.description ?? "", ...item.tags].join(" ").toLowerCase();
    return (
      (filters.archived || !item.archived) &&
      haystack.includes(filters.query.trim().toLowerCase()) &&
      filters.tags.every((tag) => item.tags.includes(tag)) &&
      (!filters.starred || item.starred)
    );
  }

  function find(id: string) {
    return dashboards.value.find((item) => item.id === id);
  }

  function highlight(...ids: string[]) {
    highlighted.value = ids;
    setTimeout(() => {
      if (highlighted.value === ids) highlighted.value = [];
    }, 4000);
  }

  const actions = {
    search(query: string) {
      filters.query = query;
      filters.page = 1;
    },
    toggleTag(tag: string) {
      filters.tags = filters.tags.includes(tag)
        ? filters.tags.filter((item) => item !== tag)
        : [...filters.tags, tag];
      filters.page = 1;
    },
    setStarredOnly(value: boolean) {
      filters.starred = value;
      filters.page = 1;
    },
    setArchived(value: boolean) {
      filters.archived = value;
      filters.page = 1;
    },
    setSort(sort: Sort) {
      filters.sort = sort;
    },
    setPage(page: number) {
      filters.page = Math.min(Math.max(1, page), pages.value);
    },
    clearFilters() {
      Object.assign(filters, { query: "", tags: [], starred: false, page: 1 });
    },
    toggleStar(id: string) {
      const item = find(id);
      if (item) item.starred = !item.starred;
    },
    duplicate(id: string, name: string) {
      const source = find(id);
      if (!source) return;
      const copy = { ...source, id: `${id}-copy-${Date.now()}`, name, starred: false };
      Object.assign(copy, { updatedAt: NOW, updatedBy: you, lastViewedAt: null });
      dashboards.value = [copy, ...dashboards.value];
      highlight(copy.id);
      notice.value = {
        text: `Created “${name}”.`,
        action: { label: "Open", run: () => visit(dashboardPath(copy.id)) },
      };
    },
    archive(id: string) {
      const item = find(id);
      if (!item) return;
      item.archived = true;
      notice.value = {
        text: `Archived “${item.name}”. It no longer appears in playlists or search.`,
        action: { label: "Undo", run: () => actions.restore(id, false) },
      };
    },
    restore(id: string, announce = true) {
      const item = find(id);
      if (!item) return;
      item.archived = false;
      notice.value = announce ? { text: `Restored “${item.name}”.` } : null;
      highlight(id);
    },
    // A teammate creates one dashboard and renames another; the list follows live.
    teammateSaves() {
      const created = teammateDashboard();
      const renamed = find("comms-health");
      dashboards.value = [created, ...dashboards.value];
      if (renamed)
        Object.assign(renamed, {
          name: "Comms & RF Health",
          updatedAt: NOW,
          updatedBy: "Avery Kim",
        });
      highlight(created.id, "comms-health");
    },
    dismissNotice() {
      notice.value = null;
    },
  };

  function visit(href: string) {
    notice.value = { text: `Prototype: this opens ${href}.` };
  }

  return reactive({
    author,
    filters,
    tags,
    filtered,
    rows,
    total: computed(() => active.value.length),
    pages,
    range,
    starred,
    recent,
    notice,
    highlighted,
    empty: computed(() => dashboards.value.length === 0),
    actions,
    visit,
  });
}

function order(sort: Sort) {
  return (a: StudyDashboard, b: StudyDashboard) => {
    if (sort === "updated") return b.updatedAt - a.updatedAt;
    const byName = a.name.localeCompare(b.name);
    return sort === "name-asc" ? byName : -byName;
  };
}

const relative = new Intl.RelativeTimeFormat("en", { numeric: "auto", style: "short" });

export function ago(time: number) {
  const minutes = Math.round((time - NOW) / 60_000);
  if (Math.abs(minutes) < 1) return "just now";
  if (Math.abs(minutes) < 60) return relative.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 24) return relative.format(hours, "hour");
  const days = Math.round(hours / 24);
  if (Math.abs(days) < 45) return relative.format(days, "day");
  return relative.format(Math.round(days / 30), "month");
}
