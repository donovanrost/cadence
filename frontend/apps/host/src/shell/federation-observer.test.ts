import { afterEach, expect, test, vi } from "vite-plus/test";
import { observeFederationRoots } from "./federation-observer";

let observer: MutationObserver | undefined;
afterEach(() => {
  observer?.disconnect();
  document.body.innerHTML = "";
});

test("in-place placement and filter changes refresh the host after the DOM update", async () => {
  document.body.innerHTML = '<div id="cadence-federation-root"></div>';
  const root = document.querySelector<HTMLElement>("#cadence-federation-root")!;
  const refresh = vi.fn(() => ({ ...root.dataset }));
  observer = observeFederationRoots(document.body, refresh);

  root.dataset.missionId = "mission-2";
  root.dataset.queryParams = '{"status":"pending"}';
  await Promise.resolve();

  expect(refresh).toHaveBeenCalledTimes(1);
  expect(refresh.mock.results[0]?.value).toMatchObject({
    missionId: "mission-2",
    queryParams: '{"status":"pending"}',
  });
});

test("screen replacement refreshes mounts, while visual state changes do not", async () => {
  const refresh = vi.fn();
  observer = observeFederationRoots(document.body, refresh);
  const root = document.createElement("div");
  document.body.append(root);
  await Promise.resolve();
  expect(refresh).toHaveBeenCalledTimes(1);

  root.className = "sidebar-collapsed";
  root.setAttribute("aria-expanded", "false");
  await Promise.resolve();
  expect(refresh).toHaveBeenCalledTimes(1);

  root.remove();
  await Promise.resolve();
  expect(refresh).toHaveBeenCalledTimes(2);
});
