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
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Commanding.RequestValidation
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
    {:ok, token} =
      Repo.transaction(fn ->
        {:ok, snapshot} = ActiveBasis.command_catalog_snapshot(c.org, c.mission)
        snapshot.token
      end)

    token
  end

  # A new generation: the fleet re-pinned, and the generation counter moved on.
  defp new_generation!(c, manifests, edit \\ fn _id, entry -> entry end) do
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

  # A fleet entry as `pin_fleet!/2` builds one, with `changes` on top.
  defp entry(c, id, changes) do
    {:ok, entries} =
      FleetSnapshot.entries(
        JsonDocument.unwrap_value(Repo.get!(ActiveBindingSetRow, c.mission).metadata)
      )

    Map.merge(Map.fetch!(entries, id), changes)
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

    test "and so does one that renames the craft's telemetry bindings (their ids embed the revision)",
         c do
      before = token(c)

      new_generation!(c, all_on(c, c.manifests.head), fn id, entry ->
        Map.put(entry, "telemetry_capability_ids", [
          "telemetry:#{c.manifests.head["revision_id"]}:#{id}"
        ])
      end)

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

    test "a change to a craft's command plan changes the fleet's command digest", c do
      digest = fn manifest ->
        {:ok, fleet} =
          FleetSnapshot.store(
            c.mission,
            Map.new(c.spacecraft, fn id ->
              {id, entry(c, id, %{"mission_model" => manifest})}
            end)
          )

        {:ok, digest} = FleetSnapshot.command_digest(FleetSnapshot.metadata(fleet, nil))
        digest
      end

      base = c.manifests.base
      other_plan = put_in(base, ["plans", "command", "plan_id"], "mission_model_plan:other")
      other_revision = Map.put(base, "revision_id", "mission_model_revision:other")
      other_monitoring = put_in(base, ["plans", "monitoring", "plan_id"], "mission_model_plan:m")

      refute digest.(other_plan) == digest.(base)
      # Neither the revision it runs nor its other plans are what a command resolves against.
      assert digest.(other_revision) == digest.(base)
      assert digest.(other_monitoring) == digest.(base)
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

  describe "a queued request's release basis" do
    setup c do
      draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

      {:ok, group} =
        GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

      members = GroupStore.members(c.org, c.mission, group.command_group_id)
      Map.put(c, :member, hd(members))
    end

    test "still resolves once its craft runs the head (the command plan is exactly the same)",
         c do
      assert {:ok, %{runtime_plan_id: plan_id}} =
               RequestValidation.resolve_basis_of(c.org, c.mission, c.member)

      assert plan_id == RequestValidation.pinned_plan_id(c.member)
      before_revision = c.member.mission_model_revision_id
      assert before_revision == c.manifests.base["revision_id"]

      new_generation!(c, all_on(c, c.manifests.head))

      # The craft runs the head revision now, and the request still pins the base's.
      assert {:ok, %{runtime_plan_id: ^plan_id}} =
               RequestValidation.resolve_basis_of(c.org, c.mission, c.member)
    end

    test "is refused when the command plan it pinned isn't the one its craft runs", c do
      new_generation!(c, all_on(c, c.manifests.head))

      other =
        put_in(
          c.member.metadata,
          ["validation_basis", "runtime_plan_id"],
          "mission_model_plan:old"
        )

      assert {:error, {:mission_model_revision_mismatch, _requested, _active}} =
               RequestValidation.resolve_basis_of(c.org, c.mission, %{c.member | metadata: other})

      # A request that pinned no plan can't be shown to have the same one: refused as well.
      assert {:error, {:mission_model_revision_mismatch, _, _}} =
               RequestValidation.resolve_basis_of(c.org, c.mission, %{c.member | metadata: %{}})
    end
  end
end
