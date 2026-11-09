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
  alias Cadence.Commanding.Groups.{CommandGroup, Validation}
  alias Cadence.Comms.UplinkResolution
  alias Cadence.Reads.{CommandGroups, Passes}

  @contact_horizon_s 6 * 3_600
  @open_queue_states [:pending, :release_pending]

  @spec run(binary(), binary(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run(organization_id, mission_id, requested_by, draft) do
    draft = %{
      draft
      | targets: UplinkResolution.annotate(organization_id, mission_id, draft.targets)
    }

    case Validation.validate(organization_id, mission_id, requested_by, draft) do
      {:ok, validated} ->
        {:ok, result(organization_id, mission_id, draft, validated)}

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

    with {:ok, preflight} <- run(organization_id, mission_id, group.requested_by, draft) do
      changed? = preflight.digest != group.preflight["digest"]
      drift = check(:changed_since_submit, if(changed?, do: :hold, else: :go), [], %{})
      {:ok, %{preflight | checks: preflight.checks ++ [drift]}}
    end
  end

  defp result(org, mission, draft, validated) do
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
      conflicts_check(org, mission, lanes),
      contact_check(org, mission, draft, validated.targets),
      two_person_check(validated.policy)
    ]

    %{
      valid?: validated.valid?,
      digest: validated.digest,
      snapshot: validated.snapshot,
      policy: validated.policy,
      targets: validated.targets,
      members: length(validated.members),
      checks: checks
    }
  end

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
  defp conflicts_check(_org, _mission, []), do: check(:conflicts, :go, [], %{count: 0})

  defp conflicts_check(org, mission, lanes) do
    lane_set = MapSet.new(lanes)

    queued =
      org
      |> Commanding.list_command_queue_entries(mission)
      |> Enum.filter(
        &(&1.lifecycle_state in @open_queue_states and MapSet.member?(lane_set, &1.queue_lane_key))
      )

    pending =
      org
      |> Commanding.list_command_requests(mission)
      |> Enum.filter(
        &(&1.lifecycle_state == :approval_pending and
            MapSet.member?(lane_set, &1.source_endpoint_ref))
      )

    ids = Enum.map(queued, & &1.command_request_id) ++ Enum.map(pending, & &1.command_request_id)
    result = if ids == [], do: :go, else: :hold
    check(:conflicts, result, [], %{count: length(ids), command_request_ids: Enum.uniq(ids)})
  end

  defp contact_check(org, mission, draft, targets) do
    now = DateTime.utc_now()
    until = Map.get(draft, :expires_at) || DateTime.add(now, @contact_horizon_s)
    until = if DateTime.compare(until, now) == :gt, do: until, else: DateTime.add(now, 60)

    next =
      org
      |> Passes.load(mission, now, until, %{states: ["confirmed", "active"]})
      |> Map.fetch!(:passes)
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
          next_contact: contact
        }
      end)

    result = if Enum.all?(per_target, &(&1.result == :go)), do: :go, else: :hold
    check(:contact, result, per_target, %{until: until})
  end

  defp two_person_check(%{second_go_required: false}),
    do: check(:two_person, :go, [], %{reasons: []})

  defp two_person_check(%{reasons: reasons}),
    do: check(:two_person, :hold, [], %{reasons: reasons})

  defp check(key, result, per_target, evidence),
    do: %{key: key, result: result, per_target: per_target, evidence: evidence}

  defp reason_key({key, _detail}) when is_atom(key), do: key
  defp reason_key(key) when is_atom(key), do: key
  defp reason_key(_other), do: :invalid
end
