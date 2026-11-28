import { expect, test, vi } from "vite-plus/test";
import { createMemoryHistory } from "vue-router";
import { createHostRouter } from "./host-navigation";

// Since #708 the catalog has no route this host serves, so link interception (installHostNavigation)
// and route resolution have nothing to exercise; only the router's history ownership is left (#668
// deletes the host).
test("a host releases only its own history subscriptions", async () => {
  const history = createMemoryHistory();
  const remove = vi.fn();
  // oxlint-disable-next-line typescript/unbound-method -- Compare the mock function identity; this expression does not invoke it.
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
