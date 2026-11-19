defmodule Cadence.Reads.CatalogDiffDBTest do
  @moduledoc """
  #367: a model revision that isn't stored is unreadable, never an empty model. Either direction
  gives a nil diff, so C3's `diff` and the revision read's `breaking` are null, never 0.
  """
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures
  alias Cadence.Reads.{CatalogDeclarations, CatalogDiff}
  alias Cadence.Repo

  setup do
    c = CommandReviewFixtures.scope!()
    Fixtures.activate!(c.org, c.mission, "")
    Map.put(c, :revision_id, CatalogDeclarations.active_revision_id(c.org, c.mission))
  end

  test "a stored revision against itself is readable and breaks nothing", c do
    assert %{summary: %{breaking: 0}, changes: []} =
             CatalogDiff.diff(c.org, c.mission, c.revision_id, c.revision_id)

    assert {commands, telemetry} = CatalogDiff.counts(c.org, c.mission, c.revision_id)
    assert is_integer(commands) and is_integer(telemetry)
  end

  test "a missing base is unreadable, not an empty model (every item added, 0 breaking)", c do
    assert CatalogDiff.diff(c.org, c.mission, "mission_model_revision:missing", c.revision_id) ==
             nil
  end

  test "a missing new revision is unreadable, not an empty model (every item removed)", c do
    assert CatalogDiff.diff(c.org, c.mission, c.revision_id, "mission_model_revision:missing") ==
             nil

    assert CatalogDiff.counts(c.org, c.mission, "mission_model_revision:missing") == {nil, nil}
  end

  # api: what the LEFT JOIN is for. An inner join would read these stored revisions as missing.
  for {label, sql} <- [
        {"an empty declarations map",
         "jsonb_set(revision_document, '{value,declarations}', '{}'::jsonb)"},
        {"no declarations key", "revision_document #- '{value,declarations}'"}
      ] do
    test "a stored revision with #{label} reads as empty, not missing", c do
      Repo.query!(
        "UPDATE mission_model_revisions SET revision_document = #{unquote(sql)} " <>
          "WHERE organization_id = $1 AND mission_id = $2 AND revision_id = $3",
        [c.org, c.mission, c.revision_id]
      )

      assert CatalogDiff.counts(c.org, c.mission, c.revision_id) == {0, 0}

      assert %{summary: %{breaking: 0}} =
               CatalogDiff.diff(c.org, c.mission, c.revision_id, c.revision_id)
    end
  end

  test "another mission's revision is missing here too", c do
    other = CommandReviewFixtures.scope!()

    assert CatalogDiff.diff(other.org, other.mission, c.revision_id, c.revision_id) == nil
  end
end
