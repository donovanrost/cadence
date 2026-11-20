defmodule Cadence.Configuration.ChangeSetReviewLandingGuardTest do
  @moduledoc """
  #117 step 2's landing guard (domain, DECISIONS #112; qa's reset pre-check): migration
  20261121090000 refuses before any DDL while mission_config_reviews or mission_config_revisions
  has rows. Both are append-only, so an existing row could never get the required fields. The
  remedy is a dev reset, never a trigger-disabled DELETE.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Configuration.Ledger

  # The migration's own SQL (api-ops on #616: inline, so a replay never needs app code).
  @migration "repo/migrations/20261121090000_change_set_review_record.exs"

  setup_all do
    path = Path.join(to_string(:code.priv_dir(:cadence)), @migration)
    [{module, _bytecode} | _] = Code.require_file(path)
    %{guard: module.guard_sql()}
  end

  test "it passes on an empty ledger", c do
    assert {:ok, _} = Repo.query(c.guard)
  end

  test "it refuses while a revision exists, naming the counts and the remedy", c do
    org = "org-guard-#{System.unique_integer([:positive])}"
    mission = "mission-guard-#{System.unique_integer([:positive])}"
    persist_mission_scope(org, mission)
    # The first ledger touch writes the mission's baseline revision.
    assert %{revision_number: 1} = Ledger.lock_head(org, mission)

    assert {:error, %Postgrex.Error{postgres: %{message: message}}} =
             Repo.query(c.guard)

    assert message =~ "mission_config_reviews has 0 row(s), mission_config_revisions has 1 row(s)"
    assert message =~ "dev reset"
    assert message =~ "Never a trigger-disabled DELETE"
  end
end
