defmodule Cadence.Reads.CommandPreflight do
  @moduledoc """
  The GO / NO-GO poll for a command-group draft (M18, docs/apogee/domain/group-requests.md §5).
  Read-only: it runs the same unlocked validation submit uses and adds the
  facts only reads can see (other work on the same lanes, each target's next
  booked contact).

  Each check is `%{key, result: :go | :hold | :no_go, per_target, evidence}`.
  The server computes facts and the UI writes the sentences. Checks the
  backend can't compute (plan impact, umbra margin) are absent, never `:go`.
  """

  alias Cadence.Commanding
  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore, Validation}
  alias Cadence.Comms.UplinkResolution
  alias Cadence.Control.WithdrawnPins
  alias Cadence.Reads.{CommandGroups, CompositionActors, Passes}
  alias Cadence.Reads.CommandPreflight.{ResolvedArguments, VerifierGroups}

  @contact_horizon_s 6 * 3_600
  # DECISIONS #60: HOLDs the submitter may acknowledge with a note. Every other HOLD is hard.
  # `model_approval_withdrawn` (E2c, #546): a craft is still on a model whose approval was taken
  # back. Commanding it stays possible, but a person says so.
  @ackable_holds [:conflicts, :model_approval_withdrawn]
  @open_queue_states [:pending, :release_pending]

  @doc """
  Runs the poll for a draft. Option `:exclude_request_ids` leaves those
  requests out of `conflicts` (review passes the group's own members).
  """
  @spec run(binary(), binary(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(organization_id, mission_id, requested_by, draft, opts \\ []) do
    draft = %{
      draft
      | targets: UplinkResolution.annotate(organization_id, mission_id, draft.targets)
    }

    case Validation.validate(organization_id, mission_id, requested_by, draft) do
      {:ok, validated} ->
        {:ok, result(organization_id, mission_id, draft, validated, opts)}

      {:error, {:command_group_too_large, evidence}} ->
        {:ok,
         %{
           valid?: false,
           digest: nil,
           policy: nil,
           targets: [],
           members: 0,
           checks: [check(:size, :no_go, [], evidence)]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Re-runs preflight on a submitted group for review (Approve A2), adding a
  `changed_since_submit` check that HOLDs when the validated result no longer
  matches what the requester submitted (catalog, targets or values changed).
  """
  @spec review(binary(), binary(), CommandGroup.t()) ::
          {:ok, map()} | {:error, term()}
  def review(organization_id, mission_id, group) do
    draft = CommandGroups.draft_of(group)

    own =
      organization_id
      |> GroupStore.members(mission_id, group.command_group_id)
      |> Enum.map(& &1.command_request_id)

    with {:ok, preflight} <-
           run(organization_id, mission_id, group.requested_by, draft, exclude_request_ids: own) do
      changed? = preflight.digest != group.preflight["digest"]
      drift = check(:changed_since_submit, if(changed?, do: :hold, else: :go), [], %{})
      {:ok, %{preflight | checks: preflight.checks ++ [drift]}}
    end
  end

  defp result(org, mission, draft, validated, opts) do
    lanes = validated.targets |> Enum.map(& &1.source_endpoint_id) |> Enum.reject(&is_nil/1)

    checks = [
      identity_check(validated),
      catalog_check(validated),
      check(
        :size,
        :go,
        [],
        Map.merge(Validation.bounds(), %{
          targets: length(draft.targets),
          commands: length(draft.commands)
        })
      ),
      conflicts_check(
        org,
        mission,
        lanes,
        MapSet.new(Keyword.get(opts, :exclude_request_ids, []))
      ),
      contact_check(org, mission, draft, validated.targets),
      model_approval_check(org, mission, validated.targets),
      two_person_check(validated.policy)
    ]

    # U51: each target's catalog revision, and where targets differ in what verifies a command.
    revisions = VerifierGroups.catalog_revisions(org, mission, validated.members)
    by_index = Map.new(validated.targets, &{&1.index, &1})

    %{
      valid?: validated.valid?,
      digest: validated.digest,
      snapshot: validated.snapshot,
      policy: validated.policy,
      targets:
        Enum.map(validated.targets, &Map.put(&1, :catalog_revision, Map.get(revisions, &1.index))),
      commands:
        draft.commands
        |> VerifierGroups.commands(validated.members, by_index, revisions)
        |> with_resolved(
          ResolvedArguments.for_preflight(org, mission, validated.members, by_index)
        ),
      members: length(validated.members),
      checks: checks
    }
  end

  # U68 R1: where the server's values differ from what was entered, per stacked command.
  defp with_resolved(commands, resolved),
    do: Enum.map(commands, &Map.put(&1, :resolved_arguments, Map.get(resolved, &1.position, [])))

  defp identity_check(%{identity_failures: []}), do: check(:identity, :go, [], %{})

  defp identity_check(%{identity_failures: failures}) do
    # `routes` names the competing (or missing) uplink routes for profile routing links.
    per_target =
      Enum.map(failures, fn failure ->
        %{
          spacecraft_id: failure.spacecraft_id,
          result: :no_go,
          reason: failure.failure,
          routes: Map.get(failure, :failure_detail, [])
        }
      end)

    check(:identity, :no_go, per_target, %{count: length(failures)})
  end

  defp catalog_check(%{catalog_failures: []}), do: check(:catalog, :go, [], %{})

  defp catalog_check(%{catalog_failures: failures}) do
    per_target =
      failures
      |> Enum.group_by(& &1.spacecraft_id)
      |> Enum.map(fn {id, rows} ->
        %{
          spacecraft_id: id,
          result: :no_go,
          reason:
            Enum.map(
              rows,
              &%{position: &1.position, command_id: &1.command_id, reason: reason_key(&1.reason)}
            )
        }
      end)

    check(:catalog, :no_go, per_target, %{count: length(failures)})
  end

  # Open work already on the targets' lanes: queued or releasing entries, plus requests
  # waiting for approval.
  defp conflicts_check(_org, _mission, [], _own), do: check(:conflicts, :go, [], %{count: 0})

  defp conflicts_check(org, mission, lanes, own) do
    # Only the open work on these lanes is read (in SQL), never the mission's whole history.
    queued =
      Commanding.list_command_queue_entries(org, mission,
        queue_lane_keys: lanes,
        lifecycle_states: @open_queue_states
      )

    pending =
      Commanding.list_command_requests(org, mission,
        source_endpoint_refs: lanes,
        lifecycle_state: :approval_pending
      )

    ids =
      (Enum.map(queued, & &1.command_request_id) ++ Enum.map(pending, & &1.command_request_id))
      |> Enum.reject(&MapSet.member?(own, &1))

    result = if ids == [], do: :go, else: :hold
    ids = ids |> Enum.uniq() |> Enum.sort()
    check(:conflicts, result, [], %{count: length(ids), command_request_ids: ids})
  end

  # A commandable contact: a confirmed or active booking whose uplink leg the provider confirmed
  # (it carries the command window), overlapping the release window [not_before or now,
  # expires_at or +6 h] (qa #35: the window ignored not_before).
  defp contact_check(org, mission, draft, targets) do
    now = DateTime.utc_now()
    from = later(Map.get(draft, :not_before), now)
    until = Map.get(draft, :expires_at) || DateTime.add(from, @contact_horizon_s)
    until = if DateTime.compare(until, from) == :gt, do: until, else: DateTime.add(from, 60)

    # Only the targets' passes, and all of them (paged by the keyset until the read is complete):
    # "no contact" is never decided from a truncated read (#1040).
    filters = %{
      states: ["confirmed", "active"],
      spacecraft_ids: Enum.map(targets, & &1.spacecraft_id)
    }

    case Passes.load_all(org, mission, from, until, filters, contact_pages()) do
      {:ok, passes} ->
        contact_result(passes, targets, from, until)

      {:error, :truncated} ->
        check(:contact, :no_go, [], %{from: from, until: until, reason: :contact_read_truncated})
    end
  end

  # How many pages of 500 the contact read may take before it gives up (`config :cadence,
  # :command_preflight_contact_pages`): past it the answer is a `contact_read_truncated` NO-GO.
  defp contact_pages, do: Application.get_env(:cadence, :command_preflight_contact_pages, 40)

  defp contact_result(passes, targets, from, until) do
    next =
      passes
      |> Enum.filter(&(&1.uplink_confirmed == true and DateTime.compare(&1.ends_at, from) == :gt))
      |> Enum.group_by(& &1.spacecraft_id)
      |> Map.new(fn {id, [first | _]} ->
        {id,
         %{
           station_code: first.station.code || first.station.ref,
           aos: first.starts_at,
           los: first.ends_at
         }}
      end)

    per_target =
      Enum.map(targets, fn target ->
        contact = Map.get(next, target.spacecraft_id)

        %{
          spacecraft_id: target.spacecraft_id,
          result: if(contact, do: :go, else: :hold),
          reason: if(contact, do: nil, else: :no_commandable_contact),
          next_contact: contact
        }
      end)

    result = if Enum.all?(per_target, &(&1.result == :go)), do: :go, else: :hold
    check(:contact, result, per_target, %{from: from, until: until})
  end

  defp later(nil, now), do: now
  defp later(%DateTime{} = at, now), do: if(DateTime.compare(at, now) == :gt, do: at, else: now)

  # E2c (#546): a target whose ACTIVE generation runs a revision whose approval was withdrawn
  # (`Control.WithdrawnPins`, keyed on what the craft runs, since that's the model a command is
  # encoded and verified against). An ackable HOLD, never a NO-GO: the craft keeps its last
  # generation and telemetry keeps flowing (E2 design, §5). Each held target carries the facts the
  # console's words need (the decision's who, when and why, and the composition it was on). The
  # basis covers exactly those craft on exactly those decisions, so a later withdrawal, or one more
  # craft on the same revision, needs its own acknowledgement.
  defp model_approval_check(org, mission, targets) do
    pins = WithdrawnPins.for_spacecraft(org, mission, Enum.map(targets, & &1.spacecraft_id))

    compositions =
      CompositionActors.for_revisions(
        org,
        mission,
        pins |> Map.values() |> Enum.map(& &1.revision_id)
      )

    per_target =
      Enum.map(targets, fn target ->
        case Map.get(pins, target.spacecraft_id) do
          nil -> %{spacecraft_id: target.spacecraft_id, result: :go}
          pin -> held_target(target.spacecraft_id, pin, Map.get(compositions, pin.revision_id))
        end
      end)

    held = Enum.filter(per_target, &(&1.result == :hold))

    evidence = %{
      count: length(held),
      composed: Enum.any?(held, &composed?(&1.composition))
    }

    basis = WithdrawnPins.basis(Map.take(pins, Enum.map(held, & &1.spacecraft_id)))

    check(
      :model_approval_withdrawn,
      if(held == [], do: :go, else: :hold),
      per_target,
      evidence,
      basis
    )
  end

  defp held_target(spacecraft_id, pin, composition) do
    %{
      spacecraft_id: spacecraft_id,
      result: :hold,
      reason: :model_approval_withdrawn,
      revision_id: pin.revision_id,
      kind: pin.decision.kind,
      decided_by: Map.take(pin.decision.by || %{}, [:id, :name]),
      decided_at: pin.decision.at,
      reason_text: pin.decision.reason,
      composition: composition
    }
  end

  defp composed?(%{imported_layers: layers}), do: length(layers) > 1
  defp composed?(_none), do: false

  # Not a HOLD (DECISIONS #60/#61): it never blocks submit, and the second GO is what satisfies it.
  # Until then it reads `second_go` ("needs a second GO"), never `go`.
  defp two_person_check(%{second_go_required: false}),
    do: check(:two_person, :go, [], %{reasons: []})

  defp two_person_check(%{reasons: reasons}),
    do: check(:two_person, :second_go, [], %{reasons: reasons})

  # `basis`: a HOLD whose facts aren't its per-target rows (the withdrawal's own decisions) names
  # its basis itself.
  defp check(key, result, per_target, evidence, basis \\ nil) do
    hold? = result == :hold

    %{
      key: key,
      result: result,
      per_target: per_target,
      evidence: evidence,
      ackable: if(hold?, do: key in @ackable_holds),
      hold_basis: if(hold?, do: basis || hold_basis(key, per_target, evidence))
    }
  end

  # The HOLD's facts, so an acknowledgement can't carry over to a changed HOLD (#60). Time-only
  # evidence (the contact window) is left out of the hash.
  defp hold_basis(key, per_target, evidence) do
    {key, per_target, Map.drop(evidence, [:from, :until])}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 32)
  end

  @doc """
  DECISIONS #60/#61: the HOLDs of `preflight` that `acks` (`[%{key, hold_basis, note}]`) don't
  satisfy, and the acks that do. An ack counts only for a current, acknowledgeable HOLD with the
  same `hold_basis`; hard HOLDs must clear. With several acks for one key, the first whose basis
  matches wins (list carried acks first so an unchanged HOLD isn't acknowledged twice).
  """
  @spec holds(map(), [map()]) :: %{unsatisfied: [map()], accepted: [map()]}
  def holds(%{checks: checks}, acks) do
    by_key = Enum.group_by(acks, &to_string(&1.key))

    Enum.reduce(checks, %{unsatisfied: [], accepted: []}, fn
      %{result: :hold} = check, acc ->
        ack =
          by_key
          |> Map.get(Atom.to_string(check.key), [])
          |> Enum.find(&(&1.hold_basis == check.hold_basis))

        if check.ackable && ack,
          do: %{acc | accepted: acc.accepted ++ [Map.put(ack, :evidence, check.evidence)]},
          else: %{
            acc
            | unsatisfied: acc.unsatisfied ++ [Map.take(check, [:key, :ackable, :hold_basis])]
          }

      _check, acc ->
        acc
    end)
  end

  defp reason_key({key, _detail}) when is_atom(key), do: key
  defp reason_key(key) when is_atom(key), do: key
  defp reason_key(_other), do: :invalid
end
