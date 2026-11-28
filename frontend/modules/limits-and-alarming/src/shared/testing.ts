import type { Page } from "./contracts";
export const emptyPage = <T>(): Page<T> => ({
  items: [],
  total_count: 0,
  page: 1,
  page_size: 25,
  previous_href: null,
  next_href: null,
});
