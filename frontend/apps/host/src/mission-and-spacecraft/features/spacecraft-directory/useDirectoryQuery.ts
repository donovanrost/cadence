import { onBeforeUnmount, ref, watch } from "vue";
import type { NavigateDirectory, Roster } from "./contracts";
import { directoryHref } from "./query";

export function useDirectoryQuery(
  roster: () => Roster,
  navigate: NavigateDirectory,
  navigating: () => boolean,
) {
  const search = ref(roster().search);
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(
    () => roster().search,
    (value) => {
      if (!timer) search.value = value;
    },
  );
  const cancel = () => {
    clearTimeout(timer);
    timer = undefined;
  };
  onBeforeUnmount(cancel);
  // Navigation starts before the old page unmounts. Its scheduled search must
  // not redirect the operator back while the destination is being authorized.
  watch(navigating, (pending) => {
    if (pending) cancel();
  });
  watch(
    () => roster().filter,
    () => {
      cancel();
      search.value = roster().search;
    },
  );
  function submit() {
    cancel();
    navigate(directoryHref(roster(), { q: search.value, page: 1 }), true);
  }
  function searchChanged(event: Event) {
    search.value = (event.target as HTMLInputElement).value;
    cancel();
    timer = setTimeout(submit, 300);
  }
  function sort(column: Roster["sort_by"]) {
    cancel();
    navigate(
      directoryHref(roster(), {
        q: search.value,
        sort: column,
        dir: roster().sort_by === column && roster().sort_dir === "asc" ? "desc" : "asc",
        page: 1,
      }),
    );
  }
  function paginate(page: number) {
    cancel();
    navigate(directoryHref(roster(), { q: search.value, page }));
  }
  return { search, searchChanged, submit, sort, paginate };
}
