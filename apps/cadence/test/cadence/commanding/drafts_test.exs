defmodule Cadence.Commanding.DraftsTest do
  @moduledoc "The draft store: optimistic revisions, consume-on-submit and the idle purge."
  use Cadence.DataCase, async: true

  alias Cadence.Commanding.Drafts

  @owner {"org-drafts", "mission-drafts", "user-1"}
  @now ~U[2026-11-11 12:00:00.000000Z]

  test "consume deletes only the revision a group was submitted from" do
    {:ok, %{revision: 1}} = Drafts.put(@owner, %{"stack" => []}, nil, nil, @now)
    {:ok, %{revision: 2}} = Drafts.put(@owner, %{"stack" => []}, 1, nil, @now)

    # Submitted from revision 1, but another tab has saved 2 since: keep it.
    assert :ok = Drafts.consume(@owner, 1)
    assert {:ok, %{revision: 2}} = Drafts.fetch(@owner, @now)

    assert :ok = Drafts.consume(@owner, 2)
    assert {:error, :command_draft_not_found} = Drafts.fetch(@owner, @now)
    assert :ok = Drafts.consume(@owner, nil)
  end

  test "a draft idle past 30 days reads as gone and a first save starts over" do
    {:ok, _} = Drafts.put(@owner, %{"stack" => []}, nil, nil, @now)
    later = DateTime.add(@now, 31 * 86_400)

    assert {:error, :command_draft_not_found} = Drafts.fetch(@owner, later)
    assert {:ok, %{revision: 1}} = Drafts.put(@owner, %{"stack" => []}, nil, nil, later)
  end
end
