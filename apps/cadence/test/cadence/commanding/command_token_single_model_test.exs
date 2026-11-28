defmodule Cadence.Commanding.CommandTokenSingleModelTest do
  @moduledoc """
  #1107: a single-model activation (no fleet entries) has nothing per craft to narrow the token
  to, and a monitoring apply moves only a fleet. So its token stays as strict as it was before:
  any new generation changes it.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Reads.MissionModels.ActiveBasis

  setup do
    setup!(1)
  end

  defp token(c) do
    {:ok, token} =
      Repo.transaction(fn ->
        {:ok, snapshot} = ActiveBasis.command_catalog_snapshot(c.org, c.mission)
        snapshot.token
      end)

    token
  end

  test "is the same while nothing changes, and moves with the generation", c do
    before = token(c)
    assert token(c) == before

    # The same model, activated again: a new generation.
    Cadence.MissionModelFixtures.activate_imported_model!(c.org, c.mission, %{
      "mission_model" => %{"revision_id" => c.revision_id}
    })

    refute token(c) == before
  end
end
