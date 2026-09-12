export type ReadContext = { missionId: string };
export type Navigation = {
  fallback_href: string;
  breadcrumbs: Array<{ label: string; href: string | null }>;
};
export type Collection<Row> = {
  navigation: Navigation;
  data: {
    title: string;
    items: Row[];
    page: number;
    page_size: number;
    page_count: number;
    total_count: number;
    query: string;
    sort: "display_name";
    dir: "asc" | "desc";
  };
};
export type Detail<Data> = { navigation: Navigation; data: Data };
