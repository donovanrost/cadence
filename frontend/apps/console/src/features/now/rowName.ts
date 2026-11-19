/**
 * U107 (a11y B7, #243): a Now row's button is named by its visible label without the trailing
 * "…", a comma, then the row's title with each " · " read as ", ". A row with no title uses its
 * position. Built once here, so every kind of row gets it.
 */
export function rowName(label: string, title: string, index: number): string {
  const object = title.trim() ? title.replaceAll(" · ", ", ") : `row ${index + 1}`;
  return `${label.replace(/…$/, "")}, ${object}`;
}
