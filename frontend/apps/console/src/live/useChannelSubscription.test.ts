import { effectScope, nextTick, ref } from "vue";
import { beforeEach, describe, expect, it, vi } from "vite-plus/test";

type Hook = () => void;
const created: FakeChannel[] = [];

class FakePush {
  hooks: Hook[] = [];
  receive(status: string, callback: Hook) {
    if (status === "ok") this.hooks.push(callback);
    return this;
  }
}

class FakeChannel {
  state = "joining";
  pushes: string[] = [];
  joinPush = new FakePush();
  left = false;
  constructor(readonly topic: string) {
    created.push(this);
  }
  join() {
    return this.joinPush;
  }
  /** Simulates a successful (re)join. */
  joinOk() {
    this.state = "joined";
    for (const hook of this.joinPush.hooks) hook();
  }
  push(event: string) {
    this.pushes.push(event);
    return new FakePush();
  }
  on() {
    return 1;
  }
  off() {}
  leave() {
    this.left = true;
    this.state = "closed";
  }
}

vi.mock("phoenix", () => ({
  Socket: class {
    onOpen() {}
    onError() {}
    onClose() {}
    connect() {}
    disconnect() {}
    channel(topic: string) {
      return new FakeChannel(topic);
    }
  },
}));

const { startSocket, stopSocket } = await import("./socket.ts");
const { useChannelSubscription } = await import("./useChannelSubscription.ts");

const messages = {
  subscribe: ["fleet:subscribe", {}],
  unsubscribe: ["fleet:unsubscribe", {}],
} as const;

describe("useChannelSubscription", () => {
  beforeEach(() => {
    stopSocket();
    created.length = 0;
    startSocket("/socket/console", "csrf");
  });

  it("subscribes after every (re)join and unsubscribes on dispose", async () => {
    const scope = effectScope();
    scope.run(() => useChannelSubscription(ref("mission:m1"), messages));
    const channel = created[0];
    expect(channel?.pushes).toEqual([]);
    channel?.joinOk();
    channel?.joinOk(); // reconnect: the server starts a fresh channel process
    expect(channel?.pushes).toEqual(["fleet:subscribe", "fleet:subscribe"]);
    scope.stop();
    await nextTick();
    expect(channel?.pushes.at(-1)).toBe("fleet:unsubscribe");
    expect(channel?.left).toBe(true);
  });

  it("moves the subscription when the topic changes and skips unsubscribe on an unjoined channel", async () => {
    const topic = ref<string | null>("mission:m1");
    const scope = effectScope();
    scope.run(() => useChannelSubscription(topic, messages));
    topic.value = "mission:m2";
    await nextTick();
    expect(created[0]?.pushes).toEqual([]);
    expect(created[0]?.left).toBe(true);
    created[1]?.joinOk();
    expect(created[1]?.pushes).toEqual(["fleet:subscribe"]);
    scope.stop();
  });

  it("resubscribe pushes unsubscribe then subscribe", () => {
    const scope = effectScope();
    const handle = scope.run(() => useChannelSubscription(ref("mission:m1"), messages));
    created[0]?.joinOk();
    handle?.resubscribe();
    expect(created[0]?.pushes).toEqual(["fleet:subscribe", "fleet:unsubscribe", "fleet:subscribe"]);
    scope.stop();
  });
});
