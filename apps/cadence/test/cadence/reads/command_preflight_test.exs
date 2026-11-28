defmodule Cadence.Reads.CommandPreflightTest do
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Activations.ActiveBindingSetRow
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Control.ModelWithdrawal
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.CommandPreflight

  setup do
    setup!(2)
  end

  defp run(c, draft), do: CommandPreflight.run(c.org, c.mission, actor(c), draft)
  defp result(checks, key), do: Enum.find(checks, &(&1.key == key))

  test "a routine draft is GO everywhere it can be; no booked contact is a HOLD per target", c do
    assert {:ok, preflight} =
             run(c, draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})]))

    assert preflight.valid?
    assert is_binary(preflight.digest)

    assert preflight.digest ==
             digest(c, draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})]))

    for key <- [:identity, :catalog, :size, :conflicts, :two_person],
        do: assert(%{result: :go} = result(preflight.checks, key))

    # No commandable contact is a hard HOLD (DECISIONS #60).
    assert %{
             result: :hold,
             ackable: false,
             hold_basis: basis,
             per_target: [%{next_contact: nil, result: :hold, reason: :no_commandable_contact}, _]
           } = result(preflight.checks, :contact)

    assert is_binary(basis)
    assert %{ackable: nil, hold_basis: nil} = result(preflight.checks, :identity)

    assert %{evidence: %{max_targets: 5_000, max_commands: 16, max_members: 20_000}} =
             result(preflight.checks, :size)

    refute Enum.any?(preflight.checks, &(&1.key in [:plan_impact, :umbra_margin]))
  end

  test "hazardous commands need a second GO, which isn't a HOLD (#60/#61)", c do
    {:ok, preflight} = run(c, draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})]))

    assert %{result: :second_go, ackable: nil, evidence: %{reasons: [%{key: :hazardous_command}]}} =
             result(preflight.checks, :two_person)

    assert preflight.policy.second_go_required
  end

  test "the contact window starts at not_before and needs a confirmed uplink (qa #35)", c do
    [sc1, sc2] = c.spacecraft
    not_before = DateTime.add(DateTime.utc_now(), 8 * 3_600)

    # sc1: a commandable pass 9 minutes after not_before, beyond the old now + 6 h horizon.
    commandable_pass!(c.org, c.mission, sc1, DateTime.add(not_before, 540))
    # sc2: a pass that ends before not_before can't carry the release.
    commandable_pass!(c.org, c.mission, sc2, DateTime.add(not_before, -3_600))

    stack = [command(c, "SET_SIGNED", %{"counter" => 1})]
    {:ok, preflight} = run(c, draft(c.spacecraft, stack, %{not_before: not_before}))

    assert %{result: :hold, per_target: per_target} = result(preflight.checks, :contact)
    by_id = Map.new(per_target, &{&1.spacecraft_id, &1})
    assert %{result: :go, next_contact: %{aos: _}} = by_id[sc1]
    assert %{result: :hold, reason: :no_commandable_contact} = by_id[sc2]
  end

  test "holds/2 accepts an ack only for a current ackable HOLD with the same basis", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])
    Enum.each(c.spacecraft, &commandable_pass!(c.org, c.mission, &1))

    {:ok, _group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, preflight} = run(c, draft)
    %{hold_basis: basis} = result(preflight.checks, :conflicts)

    assert %{unsatisfied: [%{key: :conflicts, ackable: true}], accepted: []} =
             CommandPreflight.holds(preflight, [])

    assert %{unsatisfied: [%{key: :conflicts}]} =
             CommandPreflight.holds(preflight, [%{key: "conflicts", hold_basis: "old", note: "x"}])

    assert %{unsatisfied: [], accepted: [%{key: "conflicts", note: "x", evidence: %{count: 2}}]} =
             CommandPreflight.holds(preflight, [%{key: "conflicts", hold_basis: basis, note: "x"}])

    # More work on the lanes changes the HOLD's facts, so the old ack no longer counts.
    {:ok, _another} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, changed} = run(c, draft)

    assert %{unsatisfied: [%{key: :conflicts}]} =
             CommandPreflight.holds(changed, [%{key: "conflicts", hold_basis: basis, note: "x"}])
  end

  test "work already on the lanes is a conflicts HOLD", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, _group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, preflight} = run(c, draft)

    assert %{result: :hold, ackable: true, evidence: %{count: 2}} =
             result(preflight.checks, :conflicts)
  end

  test "unknown targets are NO-GO and oversize drafts report the bounds", c do
    {:ok, preflight} = run(c, draft(["nobody"], [command(c, "SET_SIGNED", %{"counter" => 1})]))
    refute preflight.valid?

    assert %{
             result: :no_go,
             per_target: [%{spacecraft_id: "nobody", reason: :source_endpoint_not_found}]
           } =
             result(preflight.checks, :identity)

    commands = for _ <- 1..17, do: command(c, "SET_SIGNED", %{"counter" => 1})
    {:ok, oversize} = run(c, draft(c.spacecraft, commands))

    assert [%{key: :size, result: :no_go, evidence: %{max_commands: 16, commands: 17}}] =
             oversize.checks
  end

  test "review leaves the group's own members out of conflicts", c do
    draft = draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "x"})

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, review} = CommandPreflight.review(c.org, c.mission, group)
    assert %{result: :go, evidence: %{count: 0}} = result(review.checks, :conflicts)
    assert %{result: :go} = result(review.checks, :changed_since_submit)

    # A fresh draft on the same targets still sees them.
    {:ok, other} = run(c, draft)
    assert %{result: :hold, evidence: %{count: 2}} = result(other.checks, :conflicts)
  end

  # E2c (#546): a craft whose active generation runs a revision whose approval was withdrawn.
  describe "model_approval_withdrawn (the withdrawn-approval HOLD)" do
    # Every craft runs the revision the mission's active generation was imported with.
    setup c do
      row = Repo.get!(ActiveBindingSetRow, c.mission)
      metadata = JsonDocument.unwrap_value(row.metadata)

      entries =
        Map.new(c.spacecraft, fn id ->
          {id,
           %{
             "configuration_revision_id" => "rev-#{id}",
             "configuration_version" => 1,
             "catalog_revision_id" => "cat-1",
             "commanding_enabled" => true,
             "document" =>
               Map.merge(SpacecraftConfigurationInput.empty(), %{
                 "catalog_revision_id" => "cat-1",
                 "commanding_enabled" => true
               }),
             "mission_model" => metadata["mission_model"],
             "source_endpoint_ids" => [
               Cadence.SourceEndpoints.managed_source_endpoint_id(id)
             ],
             "telemetry_capability_ids" => []
           }}
        end)

      {:ok, fleet} = FleetSnapshot.store(c.mission, entries)

      Repo.update!(
        Ecto.Changeset.change(row,
          metadata:
            JsonDocument.wrap_value(Map.merge(metadata, FleetSnapshot.metadata(fleet, nil)))
        )
      )

      :ok
    end

    defp withdraw!(c) do
      assert {:ok, _} =
               ModelWithdrawal.withdraw(c.scope, c.mission, c.revision_id, "Limits were wrong")
    end

    defp routine(c), do: draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    test "an approved model is GO, with no per-target facts", c do
      {:ok, preflight} = run(c, routine(c))

      assert %{result: :go, ackable: nil, hold_basis: nil, per_target: per_target} =
               result(preflight.checks, :model_approval_withdrawn)

      assert Enum.all?(per_target, &(&1.result == :go))
    end

    test "a craft on a withdrawn revision is an ackable HOLD naming the decision", c do
      withdraw!(c)
      {:ok, preflight} = run(c, routine(c))

      assert %{
               result: :hold,
               ackable: true,
               hold_basis: basis,
               evidence: %{count: 2, composed: false},
               per_target: per_target
             } = result(preflight.checks, :model_approval_withdrawn)

      assert is_binary(basis)
      assert length(per_target) == 2

      assert [
               %{
                 result: :hold,
                 revision_id: revision_id,
                 kind: "withdrawn",
                 reason_text: "Limits were wrong",
                 decided_at: %DateTime{},
                 decided_by: %{},
                 composition: _
               }
               | _
             ] = per_target

      assert revision_id == c.revision_id

      # What the console API sends: the held rows encode as JSON (a DateTime, a named actor, the
      # composition object), and a person is never named by an email.
      json = Jason.encode!(per_target)
      refute json =~ "@"

      # It's a HOLD, not a NO-GO: the draft is still valid and the digest is there to submit.
      assert preflight.valid?
      assert is_binary(preflight.digest)
    end

    test "only the craft on the withdrawn revision are held", c do
      withdraw!(c)
      [first | _] = c.spacecraft

      {:ok, preflight} = run(c, draft([first], [command(c, "SET_SIGNED", %{"counter" => 1})]))
      assert %{evidence: %{count: 1}} = result(preflight.checks, :model_approval_withdrawn)
    end

    test "an acknowledgement covers exactly those craft on exactly that decision", c do
      withdraw!(c)
      [first, second] = c.spacecraft

      {:ok, both} = run(c, routine(c))
      check = result(both.checks, :model_approval_withdrawn)
      ack = %{key: "model_approval_withdrawn", hold_basis: check.hold_basis, note: "Seen."}

      # (The draft has no booked contact, a hard HOLD of its own; only this HOLD is asked about.)
      assert %{accepted: [accepted]} = CommandPreflight.holds(both, [ack])
      assert accepted.evidence == %{count: 2, composed: false}

      # The same decision with a different set of craft is a different HOLD.
      {:ok, one} = run(c, draft([first], [command(c, "SET_SIGNED", %{"counter" => 1})]))
      refute result(one.checks, :model_approval_withdrawn).hold_basis == check.hold_basis

      assert %{accepted: [], unsatisfied: unsatisfied} = CommandPreflight.holds(one, [ack])
      assert %{ackable: true} = Enum.find(unsatisfied, &(&1.key == :model_approval_withdrawn))

      # And a craft not on the withdrawn model brings no HOLD at all.
      assert second in c.spacecraft
    end

    test "without the acknowledgement a submit is refused, with it the group is submitted", c do
      withdraw!(c)
      # A booked, confirmed contact per craft, so this is the only HOLD left.
      for id <- c.spacecraft, do: commandable_pass!(c.org, c.mission, id)
      draft = routine(c)
      {:ok, preflight} = run(c, draft)
      check = result(preflight.checks, :model_approval_withdrawn)

      assert %{unsatisfied: [%{key: :model_approval_withdrawn, ackable: true}]} =
               CommandPreflight.holds(preflight, [])

      ack = %{key: "model_approval_withdrawn", hold_basis: check.hold_basis, note: "Seen."}
      assert %{unsatisfied: [], accepted: [_]} = CommandPreflight.holds(preflight, [ack])

      assert {:ok, _group} =
               GroupSubmission.submit(c.scope, c.mission, draft,
                 preflight_digest: preflight.digest,
                 hold_acks: [Map.put(ack, :preflight_digest, preflight.digest)]
               )
    end
  end
end
