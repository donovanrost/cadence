defmodule Cadence.Commanding.CommandTokenTest do
  @moduledoc """
  #1107: commanding's catalog token covers what commands resolve against (each craft's command
  plan, configuration revision and bindings), not the activation as a whole. A monitoring-only
  generation (craft moved to a new head revision with the same command plan) leaves it equal, so a
  pending GO and a create in flight still pass; a change to a command plan, a configuration
  revision or a binding changes it, and they are refused.
  """
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.CommandPreflight
  alias Cadence.Reads.MissionModels.ActiveBasis

  setup do
    c = setup!(3)
    manifests = head_manifests!(c)
    pin_fleet!(c, Map.new(c.spacecraft, &{&1, manifests.base}))
    Map.merge(c, %{manifests: manifests, approver: operator!(c)})
  end

  defp token(c) do
    {:ok, snapshot} = ActiveBasis.command_catalog_snapshot(c.org, c.mission)
    snapshot.token
  end

  # A new generation: the fleet re-pinned, and the generation counter moved on.
  defp new_generation!(c, manifests, edit \\ & &1) do
    pin_fleet!(c, manifests)
    row = Repo.get!(ActiveBindingSetRow, c.mission)
    metadata = JsonDocument.unwrap_value(row.metadata)
    entries = fleet_entries(metadata)

    {:ok, fleet} =
      FleetSnapshot.store(c.mission, Map.new(entries, fn {id, e} -> {id, edit.(id, e)} end))

    Repo.update!(
      Ecto.Changeset.change(row,
        generation: row.generation + 1,
        metadata: JsonDocument.wrap_value(Map.merge(metadata, FleetSnapshot.metadata(fleet, nil)))
      )
    )

    :ok
  end

  defp fleet_entries(metadata) do
    {:ok, entries} = FleetSnapshot.entries(metadata)
    entries
  end

  defp all_on(c, manifest), do: Map.new(c.spacecraft, &{&1, manifest})

  defp hazardous(c),
    do: draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "Reset"})

  test "the head's command plan is the base's: the two manifests differ only elsewhere", c do
    refute c.manifests.base["revision_id"] == c.manifests.head["revision_id"]
    assert c.manifests.base["plans"]["command"] == c.manifests.head["plans"]["command"]
  end

  describe "the token" do
    test "a monitoring-only generation leaves it equal", c do
      before = token(c)
      new_generation!(c, all_on(c, c.manifests.head))
      assert token(c) == before
    end

    test "a change to a craft's configuration revision changes it", c do
      before = token(c)

      new_generation!(c, all_on(c, c.manifests.base), fn id, entry ->
        if id == hd(c.spacecraft), do: Map.put(entry, "configuration_version", 2), else: entry
      end)

      refute token(c) == before
    end

    test "a change to a craft's bindings (its source endpoints) changes it", c do
      before = token(c)

      new_generation!(c, all_on(c, c.manifests.base), fn id, entry ->
        if id == hd(c.spacecraft),
          do: Map.put(entry, "source_endpoint_ids", ["another-endpoint"]),
          else: entry
      end)

      refute token(c) == before
    end

    test "a change to a craft's command plan changes it", c do
      before = token(c)
      other = put_in(c.manifests.base, ["plans", "command", "content_sha256"], "other-content")

      new_generation!(c, all_on(c, c.manifests.base), fn id, entry ->
        if id == hd(c.spacecraft), do: Map.put(entry, "mission_model", other), else: entry
      end)

      refute token(c) == before
    end

    test "a craft's commanding switched off changes it", c do
      before = token(c)

      new_generation!(c, all_on(c, c.manifests.base), fn id, entry ->
        if id == List.last(c.spacecraft),
          do: Map.put(entry, "commanding_enabled", false),
          else: entry
      end)

      refute token(c) == before
    end
  end

  describe "a pending GO and a create in flight" do
    test "pass a monitoring-only generation", c do
      draft = hazardous(c)
      {:ok, pre} = CommandPreflight.run(c.org, c.mission, actor(c), draft)

      # The generation lands between the preflight and the submit...
      new_generation!(c, all_on(c, c.manifests.head))

      assert {:ok, group} =
               GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: pre.digest)

      assert group.state == :approval_pending

      # ...and another between the submit and its GO.
      new_generation!(c, all_on(c, c.manifests.base))
      {:ok, review} = CommandPreflight.review(c.org, c.mission, group)
      refute Enum.any?(review.checks, &(&1.key == :changed_since_submit and &1.result != :go))

      assert {:ok, %{state: :queued}} =
               GroupDecision.decide(c.approver, c.mission, group.command_group_id, %{
                 kind: :go,
                 expected_review: GroupDecision.review_token(group)
               })
    end

    test "are refused when a configuration revision changed", c do
      draft = hazardous(c)
      {:ok, pre} = CommandPreflight.run(c.org, c.mission, actor(c), draft)

      new_generation!(c, all_on(c, c.manifests.base), fn id, entry ->
        if id == hd(c.spacecraft), do: Map.put(entry, "configuration_version", 2), else: entry
      end)

      assert {:error, :preflight_stale} =
               GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: pre.digest)
    end

    test "a pending GO is refused when a binding changed", c do
      draft = hazardous(c)
      {:ok, pre} = CommandPreflight.run(c.org, c.mission, actor(c), draft)

      {:ok, group} =
        GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: pre.digest)

      new_generation!(c, all_on(c, c.manifests.base), fn id, entry ->
        if id == hd(c.spacecraft),
          do: Map.put(entry, "commanding_enabled", true) |> Map.put("configuration_version", 3),
          else: entry
      end)

      assert {:error, :command_group_basis_changed} =
               GroupDecision.decide(c.approver, c.mission, group.command_group_id, %{
                 kind: :go,
                 expected_review: GroupDecision.review_token(group)
               })
    end
  end
end
