"""Publish the artifacts produced by a single hosted Earendil scale run."""

import os
import shutil
from pathlib import Path


def main():
    label = os.environ["SCORECARD_LABEL"]
    runner = os.environ["SCALE_RUNNER_TYPE"]
    succeeded = os.environ["SCORECARD_OUTCOME"] == "success"
    output = Path(os.environ["RUNNER_TEMP"]) / "scale-scorecard"

    series = sorted(Path("var/scale").glob(f"*-{label}.jsonl"))
    summaries = sorted(Path("var/scale").glob(f"*-{label}.summary.json"))
    pages = sorted(Path("docs/scale").glob(f"*-{label}.md"))

    if len(pages) == 1:
        page = pages[0]
        heading, _, body = page.read_text(encoding="utf-8").partition("\n\n")
        status = "" if succeeded else "**Partial run. See the measurement step for the failure.**\n\n"
        scorecard = f"{heading}\n\n{status}- Runner type {runner}\n{body}"
        page.write_text(scorecard, encoding="utf-8")
    else:
        size = os.environ["SCORECARD_SPACECRAFT"]
        shape = os.environ["SCORECARD_SHAPE"]
        scorecard = (
            f"# Scale scorecard for {size} craft ({shape})\n\n"
            f"- Runner type {runner}\n\n"
            f"Expected one Markdown scorecard and found {len(pages)}.\n"
        )

    summary = Path(os.environ["GITHUB_STEP_SUMMARY"])
    with summary.open("a", encoding="utf-8") as handle:
        handle.write(scorecard)

    for source in [*series, *summaries, *pages]:
        destination = output / source
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    if succeeded and not (len(series) == len(summaries) == len(pages) == 1):
        raise SystemExit("Expected one JSONL series, one JSON summary, and one Markdown scorecard.")


if __name__ == "__main__":
    main()
