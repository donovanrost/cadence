defmodule Cadence.Control.Commanding.GroupSubmission do
  @moduledoc """
  Submits a command group (docs/apogee/domain/group-requests.md §3), following
  domain's Q5 plan: validate every member **without** the activation lock,
  require the digest the operator's preflight showed, then a short locked
  transaction that re-checks the command-catalog snapshot and inserts the
  group, its members and (when no second GO is needed) their queue entries in
  bulk. Read updates and lane kicks happen after commit.

  The requester is always the authenticated human (DECISIONS #30).
  """

  require Logger

  alias Cadence.Commanding.{Dispatcher, Drafts, ProcessNamespace, RequestValidation}
  alias Cadence.Commanding.Groups.{Admission, CommandGroup, GroupStore, Validation}
  alias Cadence.Comms.UplinkResolution
  alias Cadence.Management.Commanding.{ApprovedCommand, RequestAuthoring}
  alias Cadence.Platform.ScopedReadUpdates

  @spec submit(Cadence.Auth.Scope.t(), binary(), map(), keyword()) ::
          {:ok, CommandGroup.t()} | {:error, term()}
  # todo(authz): Cedar should decide who may request this group (DECISIONS #62: any mission
  # operator today), e.g. by command significance, hazard, target set or fleet reach.
  def submit(scope, mission_id, draft, opts) do
    with {:ok, fresh, _mission} <- RequestAuthoring.authorize(scope, mission_id),
         org = fresh.organization_id,
         actor = %{"actor_kind" => "user", "user_id" => fresh.user.user_id},
         :ok <- not_replayed(org, mission_id, Keyword.get(opts, :operation_id)),
         :ok <- required_text(draft),
         draft = %{draft | targets: UplinkResolution.annotate(org, mission_id, draft.targets)},
         {:ok, validated} <- Validation.validate(org, mission_id, actor, draft),
         :ok <- admissible(validated, draft, Keyword.get(opts, :preflight_digest)) do
      org
      |> admit(mission_id, actor, draft, validated, opts)
      |> after_commit(org, mission_id)
    end
  end

  defp not_replayed(_org, _mission, nil), do: :ok

  defp not_replayed(org, mission, operation_id) do
    case GroupStore.fetch_by_operation(org, mission, operation_id) do
      {:ok, group} -> {:error, {:duplicate_operation, group.command_group_id}}
      {:error, :command_group_not_found} -> :ok
    end
  end

  defp required_text(draft) do
    if blank?(Map.get(draft, :title)), do: {:error, :title_required}, else: :ok
  end

  defp admissible(%{valid?: false} = validated, _draft, _digest),
    do: {:error, {:preflight_no_go, Map.take(validated, [:identity_failures, :catalog_failures])}}

  defp admissible(validated, draft, digest) do
    cond do
      validated.digest != digest ->
        {:error, :preflight_stale}

      validated.policy.second_go_required and blank?(Map.get(draft, :log_entry)) ->
        {:error, :log_entry_required}

      true ->
        :ok
    end
  end

  defp admit(org, mission, actor, draft, validated, opts) do
    {elapsed_us, result} =
      :timer.tc(fn ->
        RequestValidation.with_authoring_catalog(
          org,
          mission,
          &locked_insert(&1, org, mission, actor, draft, validated, opts)
        )
      end)

    Logger.info(
      "command group admitted: #{length(validated.members)} members, " <>
        "#{div(elapsed_us, 1000)} ms under the command-basis lock",
      mission_id: mission
    )

    result
  end

  defp locked_insert(snapshot, org, mission, actor, draft, validated, opts) do
    if snapshot.token == validated.snapshot.token and
         snapshot.activation_id == validated.snapshot.activation_id,
       do: insert(org, mission, actor, draft, validated, opts),
       else: {:error, :preflight_stale}
  end

  defp insert(org, mission, actor, draft, validated, opts) do
    second_go? = validated.policy.second_go_required
    group = build_group(org, mission, actor, draft, validated, opts, second_go?)

    members =
      Admission.members(
        group.command_group_id,
        validated.members,
        if(second_go?, do: :approval_pending, else: :queued)
      )

    with {:ok, group} <- GroupStore.insert_group(group),
         :ok <- GroupStore.insert_members(members),
         :ok <-
           Drafts.consume({org, mission, actor["user_id"]}, Keyword.get(opts, :draft_revision)) do
      queued =
        if second_go?, do: [], else: Admission.enqueue(members, actor, &auto_approved_hash/1)

      :ok =
        GroupStore.append_events([
          %{
            command_group_id: group.command_group_id,
            mission_id: mission,
            kind: :submitted,
            actor: actor,
            payload: %{"members" => length(members), "second_go_required" => second_go?}
          }
          | hold_events(group, actor, Keyword.get(opts, :hold_acks, []))
        ])

      {:ok, %{group: group, lanes: queued |> Enum.map(& &1.queue_lane_key) |> Enum.uniq()}}
    end
  end

  # DECISIONS #60: each acknowledged preflight HOLD, with who acknowledged it, the note and the
  # HOLD's basis, so the audit shows what was known when the group was armed.
  defp hold_events(group, actor, acks) do
    Enum.map(acks, fn ack ->
      %{
        command_group_id: group.command_group_id,
        mission_id: group.mission_id,
        kind: :hold_acknowledged,
        actor: actor,
        payload: %{
          "key" => ack.key,
          "note" => ack.note,
          "hold_basis" => ack.hold_basis,
          "preflight_digest" => Map.get(ack, :preflight_digest),
          "evidence" => ack |> Map.get(:evidence, %{}) |> Jason.encode!() |> Jason.decode!()
        }
      }
    end)
  end

  defp build_group(org, mission, actor, draft, validated, opts, second_go?) do
    now = DateTime.utc_now()

    CommandGroup.new(%{
      organization_id: org,
      mission_id: mission,
      state: if(second_go?, do: :approval_pending, else: :queued),
      title: String.trim(draft.title),
      log_entry: Map.get(draft, :log_entry),
      requested_by: actor,
      requested_at: now,
      requested_approver_user_id: Map.get(draft, :requested_approver_user_id),
      operation_id: Keyword.get(opts, :operation_id),
      sent_back_from: Map.get(draft, :sent_back_from),
      target_query: Map.get(draft, :target_query, %{}),
      targets: validated.targets,
      resolved_at: now,
      commands: Enum.map(validated.commands, &stringify/1) |> with_arguments(draft.commands),
      release: %{
        "not_before" => Map.get(draft, :not_before),
        "expires_at" => Map.get(draft, :expires_at),
        "priority" => Map.get(draft, :priority, 3)
      },
      basis: stringify(validated.snapshot),
      policy: stringify(validated.policy),
      preflight: %{"digest" => validated.digest},
      member_count: length(validated.members)
    })
  end

  # The stack in draft order, each with its classification and argument values.
  defp with_arguments(classified, commands) do
    by_id = Map.new(classified, &{&1["command_id"], &1})

    commands
    |> Enum.with_index()
    |> Enum.map(fn {command, position} ->
      by_id
      |> Map.get(command.command_id, %{"command_id" => command.command_id})
      |> Map.merge(%{
        "position" => position,
        "argument_values" => Map.get(command, :argument_values, %{}),
        "per_target" => Map.get(command, :per_target, %{})
      })
    end)
  end

  # Members that need no second GO carry the policy approval's content hash, as single
  # workspace submissions do.
  defp auto_approved_hash(request) do
    {:ok, approved} =
      ApprovedCommand.from_automatic_policy(%{request | lifecycle_state: :validated})

    %{"approved_content_sha256" => approved.content_sha256}
  end

  defp after_commit({:ok, %{group: group, lanes: lanes}}, org, mission) do
    ScopedReadUpdates.publish(:commanding_changed, org, mission)
    Enum.each(lanes, &Dispatcher.kick_lane(ProcessNamespace.default(), org, mission, &1))
    {:ok, group}
  end

  defp after_commit({:error, reason}, _org, _mission), do: {:error, reason}

  defp stringify(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)

  defp stringify(atom) when is_atom(atom) and atom not in [nil, true, false],
    do: Atom.to_string(atom)

  defp stringify(value), do: value

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
