import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { probeStop } from "./probe-stop.ts";

/** Focuses a stop at the given box in a 390×844 phone viewport and probes it. */
function probe(left: number, top: number, width: number, height: number) {
  const stop = document.createElement("div");
  stop.tabIndex = 0;
  stop.setAttribute("role", "region");
  stop.setAttribute("aria-label", "Spacecraft");
  stop.style.outline = "2px solid red";
  document.body.append(stop);
  vi.spyOn(stop, "getBoundingClientRect").mockReturnValue(new DOMRect(left, top, width, height));
  const pointed = vi.spyOn(document, "elementFromPoint").mockReturnValue(stop);
  stop.focus();
  return { problems: probeStop([])?.problems ?? [], pointed };
}

beforeEach(() => {
  vi.stubGlobal("innerWidth", 390);
  vi.stubGlobal("innerHeight", 844);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  document.body.replaceChildren();
});

/** #189: the sweep's geometry run at 390. */
describe("probeStop: is the focused stop on screen?", () => {
  it("passes a table region taller than the viewport whose top shows", () => {
    expect(probe(17, 56, 356, 59285).problems).toEqual([]);
  });

  it("tests the visible part of a tall stop for cover, not its centre", () => {
    expect(probe(17, 56, 356, 2264).pointed).toHaveBeenCalledWith(195, 450);
  });

  it("fails a tall stop that is wholly below the fold", () => {
    expect(probe(17, 900, 356, 2264).problems).toEqual([
      "off screen when focused (at 17,900 356×2264 in 390×844)",
    ]);
  });

  it("fails a link whose centre is cut off at the right edge", () => {
    expect(probe(369, 222, 133, 36).problems).toEqual([
      "off screen when focused (at 369,222 133×36 in 390×844)",
    ]);
  });
});

/** #868: a windowed list's rows are keyed by their place in the list, not their child index. */
describe("probeStop: stop identity", () => {
  function focusRow(place: number, childIndex: number) {
    document.body.replaceChildren();
    const ul = document.createElement("ul");
    for (let i = 0; i <= childIndex; i++) {
      const li = document.createElement("li");
      li.setAttribute("data-row-index", String(place - childIndex + i));
      const a = document.createElement("a");
      a.href = `#${place - childIndex + i}`;
      a.textContent = "craft";
      li.append(a);
      ul.append(li);
    }
    document.body.append(ul);
    const link = ul.lastElementChild?.querySelector("a");
    if (!(link instanceof HTMLElement)) throw new Error("no link");
    vi.spyOn(link, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 100, 40));
    vi.spyOn(document, "elementFromPoint").mockReturnValue(link);
    link.focus();
    return probeStop([])?.key;
  }

  it("tells apart two rows that the window put at the same child index", () => {
    expect(focusRow(24, 3)).not.toBe(focusRow(25, 3));
    expect(focusRow(25, 3)).toBe(focusRow(25, 7));
  });
});

/** #928: a named region (the staged-changes bar) is a landmark; an unnamed one isn't (ARIA). */
describe("probeStop: named regions are landmarks", () => {
  function landmarkOfButtonIn(html: string) {
    document.body.innerHTML = html;
    const button = document.querySelector("button");
    if (!(button instanceof HTMLElement)) throw new Error("no button");
    vi.spyOn(button, "getBoundingClientRect").mockReturnValue(new DOMRect(10, 10, 100, 40));
    vi.spyOn(document, "elementFromPoint").mockReturnValue(button);
    button.focus();
    return probeStop([])?.landmark;
  }

  it("names a stop in a labelled region outside main by that region", () => {
    expect(
      landmarkOfButtonIn(
        '<div role="region" aria-label="Staged changes"><button>Open review</button></div>',
      ),
    ).toBe("region 'Staged changes'");
    expect(
      landmarkOfButtonIn(
        '<h2 id="t">Changes</h2><section aria-labelledby="t"><button>Go</button></section>',
      ),
    ).toBe("region 'Changes'");
  });

  it("keeps a region inside main in main's run, and ignores an unnamed region", () => {
    expect(
      landmarkOfButtonIn(
        '<main><div role="region" aria-label="Inner"><button>x</button></div></main>',
      ),
    ).toBe("main");
    expect(landmarkOfButtonIn('<div role="region"><button>x</button></div>')).toBe("");
  });
});
