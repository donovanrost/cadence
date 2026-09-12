import { afterEach, beforeEach, expect, test, vi } from "vite-plus/test";
import type { Window as HappyWindow } from "happy-dom";
import { createMemoryHistory } from "vue-router";
import {
  createHostRouter,
  hostRoute,
  installHostNavigation,
  shellForRoute,
} from "./host-navigation";

const navigationSettings = (window as unknown as HappyWindow).happyDOM.settings.navigation;
const originalNavigationSettings = { ...navigationSettings };
beforeEach(() => {
  Object.assign(navigationSettings, {
    disableMainFrameNavigation: true,
    disableChildPageNavigation: true,
    disableFallbackToSetURL: true,
  });
});

const cleanups: (() => void)[] = [];
afterEach(() => {
  Object.assign(navigationSettings, originalNavigationSettings);
  cleanups.splice(0).forEach((cleanup) => cleanup());
  document.body.innerHTML = "";
});

test("a host releases only its own history subscriptions", async () => {
  const history = createMemoryHistory();
  const remove = vi.fn();
  const originalListen = history.listen;
  const listen = vi.spyOn(history, "listen").mockImplementation((callback) => {
    const unsubscribe = originalListen(callback);
    return () => {
      remove();
      unsubscribe();
    };
  });
  const destroy = vi.spyOn(history, "destroy");
  const first = createHostRouter(history);
  await first.replace("/missions");
  expect(listen).toHaveBeenCalledTimes(1);
  first.listening = false;
  first.options.history.destroy();
  first.options.history.destroy();
  expect(remove).toHaveBeenCalledTimes(1);
  expect(destroy).not.toHaveBeenCalled();
  const second = createHostRouter(history);
  await second.replace("/missions/new");
  expect(second.options.history.location).toBe(history.location);
  expect(second.options.history.state).toBe(history.state);
  expect(listen).toHaveBeenCalledTimes(2);
  second.listening = false;
  second.options.history.destroy();
  expect(remove).toHaveBeenCalledTimes(2);
});

test("a host disposed before initial navigation finishes cannot retain a late history listener", async () => {
  const history = createMemoryHistory();
  const listen = vi.spyOn(history, "listen");
  const router = createHostRouter(history);
  const navigation = router.replace("/missions");
  router.listening = false;
  router.options.history.destroy();
  await navigation;
  expect(listen).not.toHaveBeenCalled();
});

function clickLink(
  href: string,
  attrs = "",
  options: MouseEventInit = {},
  current = "https://cadence.test/missions/m-1",
) {
  const navigate = vi.fn();
  cleanups.push(installHostNavigation(document, { href: current } as Location, navigate));
  document.body.innerHTML = `<a href="${href}" ${attrs}><span>Open</span></a>`;
  const link = document.querySelector("a")!;
  // The browser resolves the anchor against the same origin as the current page.
  link.href = new URL(href, current).href;
  const event = new MouseEvent("click", { bubbles: true, cancelable: true, ...options });
  // Prevent the test DOM from performing native navigation for excluded links.
  const preventNative = (event: Event) => event.preventDefault();
  window.addEventListener("click", preventNative);
  cleanups.push(() => window.removeEventListener("click", preventNative));
  link.querySelector("span")!.dispatchEvent(event);
  return { link, preventedByNavigation: event.defaultPrevented, navigate };
}

test("ordinary links across feature areas are handled by the Vue host", () => {
  const { link, preventedByNavigation } = clickLink(
    "/missions/m-1/comms",
    'data-phx-link="redirect"',
  );
  expect(link.dataset.phxLink).toBe("redirect");
  expect(preventedByNavigation).toBe(true);
});

test("plain remote links and query changes use the same host navigation", () => {
  expect(clickLink("/missions/m-1/spacecraft").navigate).toHaveBeenCalledWith(
    "/missions/m-1/spacecraft",
    false,
  );
  expect(
    clickLink("/missions/m-1?filter=active", 'data-phx-link-state="replace"').link.dataset
      .phxLinkState,
  ).toBe("replace");
});

test.each([
  ["/missions/m-1/applications", "/missions/m-1/spacecraft"],
  ["/missions/m-1/spacecraft", "/missions/m-1/applications"],
  ["/missions/m-1/spacecraft/s-1/applications", "/missions/m-1/spacecraft"],
])("management navigation stays in the host: %s to %s", (from, to) => {
  const { link, preventedByNavigation } = clickLink(
    to,
    'data-phx-link="redirect"',
    {},
    `https://cadence.test${from}`,
  );
  expect(link.dataset.phxLink).toBe("redirect");
  expect(preventedByNavigation).toBe(true);
});

test.each([
  ["https://other.test/missions", "", {}, undefined],
  ["/session", "", {}, undefined],
  ["/missions/m-1/applications/comms/overview", "", {}, undefined],
  ["/missions", 'target="_blank"', {}, undefined],
  ["/missions", "download", {}, undefined],
  ["/missions", "", { ctrlKey: true }, undefined],
  ["/missions", "", { metaKey: true }, undefined],
  ["/missions", "", { button: 1 }, undefined],
  ["#details", "", {}, undefined],
  ["/missions", "", {}, "https://cadence.test/sign-in"],
])("preserves native or non-host navigation: %s %s %j", (href, attrs, options, current) => {
  const result = clickLink(href, attrs, options, current);
  expect(result.link.dataset.phxLink).toBeUndefined();
  expect(result.navigate).not.toHaveBeenCalled();
});

test("remote component handlers can cancel navigation before the host processes a link", () => {
  const navigate = vi.fn();
  cleanups.push(
    installHostNavigation(document, { href: "https://cadence.test/missions" }, navigate),
  );
  const link = document.createElement("a");
  link.href = "https://cadence.test/missions/mission-1";
  link.addEventListener("click", (event) => event.preventDefault());
  document.body.append(link);
  link.click();
  expect(navigate).not.toHaveBeenCalled();
});

test("the mission Ops entry resolves to the operational shell", () => {
  const route = hostRoute(new URL("https://cadence.test/missions/mission-1/ops"));
  expect(route?.workspacePage).toBe("landing");
  expect(shellForRoute(route!)).toBe("ops");
});
