defmodule Cadence.Control.Commanding.GroupRelease do
  @moduledoc """
  Release an armed command group onto a contact an operator names (U46, api). The lane releases a
  group by itself only into a scheduled pass (director, 11-14); this is how an operator sends one
  over a pass they choose, a hand-started contact included.

  Only the members whose target is the spacecraft that contact serves are released (a contact
  serves one spacecraft, SAFETY #38); members for other targets keep waiting for their own
  passes. They go in stack order, each through `Cadence.Commanding.release_command_queue_entry/6`,
  so the halt rule, lane order, basis re-validation, the command window and the target guard all
  apply per member. The call **stops at the first member that doesn't release**: what went out
  stays released, the rest stay queued.

  Before anything is released it refuses, as a group, a group that isn't armed (`:queued`), a
  contact that isn't a booked pass unless `confirm_unbooked: true` (ux's danger sheet, for every
  caller), a closed command window, and a contact none of the group's targets is served by.
  Past those checks the attempt is recorded on the group's timeline (`released_on_contact`), even
  when the first member stops.
  """

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  alias Cadence.Commanding.{
    Cancellation,
    CommandRequest,
    ReleaseTargetGuard,
    ReleaseTargetSelection
  }

  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore}
  alias Cadence.Contacts
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Management.Commanding, as: ManagementCommanding
  alias Cadence.Platform.ScopedReadUpdates

  @type stopped :: %{
          command_queue_entry_id: binary(),
          command_request_id: binary(),
          reason: term()
        }

  @type result :: %{
          command_group_id: binary(),
          realized_contact_id: binary(),
          released_entry_ids: [binary()],
          stopped: stopped() | nil,
          not_attempted_entry_ids: [binary()]
        }

  @doc """
  Options: `confirm_unbooked: true` to release into a contact that isn't a booked pass;
  `attempted_at:` (tests) instead of now.
  """
  @spec release(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def release(scope, mission_id, group_id, realized_contact_id, opts \\ []) do
    # todo(authz): Cedar should decide who may send a group over a pass they name (today the
    # GO/NO-GO rule: any mission operator, DECISIONS #62), e.g. not into an unbooked contact.
    with {:ok, %Scope{user: %User{user_id: user_id}} = fresh, _mission} <-
           ManagementCommanding.authorize(scope, mission_id) do
      org = fresh.organization_id
      at = Keyword.get(opts, :attempted_at, DateTime.utc_now())
      actor = %{"actor_kind" => "user", "user_id" => user_id}

      with {:ok, group} <- GroupStore.fetch(org, mission_id, group_id),
           :ok <- armed(group),
           {:ok, contact} <- Contacts.fetch_realized_contact(org, mission_id, realized_contact_id),
           :ok <- booked_or_confirmed(contact, opts),
           {:ok, _open} <-
             ReleaseTargetSelection.fetch_realized_contact(
               org,
               mission_id,
               realized_contact_id,
               at
             ),
           {:ok, members} <- releasable_members(org, mission_id, group_id, contact) do
        expired = expire(org, mission_id, members, at)
        result = release_members(org, mission_id, members, expired, contact, actor, opts)
        :ok = record(org, mission_id, group_id, contact, actor, result)
        ScopedReadUpdates.publish(:commanding_changed, org, mission_id)

        {:ok,
         Map.merge(
           %{command_group_id: group_id, realized_contact_id: realized_contact_id},
           result
         )}
      end
    end
  end

  @doc """
  The JSON-ready form of a member's refusal, `%{"code" => string, "details" => map}` (api's
  timeline payload): the code is the reason's atom (or its tuple's first element); the details
  name the rest. A closed command window also carries that contact's window (`starts_at`,
  `ends_at`, ISO 8601; `ends_at` nil when open-ended), so a reader can say "hasn't started" or
  "has ended" without another fetch.
  """
  @spec encode_reason(term(), binary(), binary()) :: %{binary() => term()}
  def encode_reason({:command_window_closed, contact_id, why}, org, mission) do
    reason(
      "command_window_closed",
      Map.merge(
        %{"realized_contact_id" => contact_id, "why" => to_string(why)},
        window(org, mission, contact_id)
      )
    )
  end

  def encode_reason({:command_release_refused, attempt_id, refusal}, org, mission),
    do:
      reason("command_release_refused", %{
        "command_release_attempt_id" => attempt_id,
        "refusal" => encode_reason(refusal, org, mission)
      })

  def encode_reason(term, _org, _mission), do: encode_reason(term)

  @doc "As `encode_reason/3`, for reasons that need no lookup."
  @spec encode_reason(term()) :: %{binary() => term()}
  def encode_reason({:command_queue_entry_not_next_for_release, _entry_id, next_id}),
    do:
      reason("command_queue_entry_not_next_for_release", %{
        "next_command_queue_entry_id" => next_id
      })

  def encode_reason({:command_queue_lane_release_pending, lane}),
    do: reason("command_queue_lane_release_pending", %{"queue_lane_key" => lane})

  def encode_reason({:command_release_outcome_uncertain, attempt_id, _cause} = term),
    do:
      reason("command_release_outcome_uncertain", %{
        "command_release_attempt_id" => attempt_id,
        "message" => inspect(term)
      })

  def encode_reason(reason) when is_atom(reason), do: reason(Atom.to_string(reason), %{})

  def encode_reason(term) when is_tuple(term) and is_atom(elem(term, 0)),
    do: reason(Atom.to_string(elem(term, 0)), %{"message" => inspect(term)})

  def encode_reason(term), do: reason("unknown", %{"message" => inspect(term)})

  # The named contact's command window: its scheduled pass (CommandWindow), or open-ended.
  defp window(org, mission, contact_id) do
    with {:ok, %RealizedContact{scheduled_contact_id: id}} when is_binary(id) <-
           Contacts.fetch_realized_contact(org, mission, contact_id),
         {:ok, scheduled} <- Contacts.fetch_scheduled_contact(org, mission, id) do
      %{"starts_at" => iso(scheduled.starts_at), "ends_at" => iso(scheduled.ends_at)}
    else
      _no_booked_window -> %{"starts_at" => nil, "ends_at" => nil}
    end
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp reason(code, details), do: %{"code" => code, "details" => details}

  defp armed(%CommandGroup{state: :queued}), do: :ok
  defp armed(%CommandGroup{state: state}), do: {:error, {:command_group_not_armed, state}}

  defp booked_or_confirmed(%RealizedContact{scheduled_contact_id: id}, _opts) when is_binary(id),
    do: :ok

  defp booked_or_confirmed(%RealizedContact{} = contact, opts) do
    if Keyword.get(opts, :confirm_unbooked) == true,
      do: :ok,
      else: {:error, {:unbooked_contact_unconfirmed, contact.realized_contact_id}}
  end

  # This contact's spacecraft's members still queued, in stack order, with their queue entries.
  defp releasable_members(org, mission, group_id, %RealizedContact{} = contact) do
    own =
      Enum.filter(GroupStore.members(org, mission, group_id), &served?(org, mission, &1, contact))

    queued = Enum.filter(own, &(&1.lifecycle_state == :queued))

    entries =
      GroupStore.pending_entry_ids(org, mission, Enum.map(queued, & &1.command_request_id))

    members =
      for %CommandRequest{command_request_id: id} <- queued,
          entry_id = entries[id],
          is_binary(entry_id),
          do: {id, entry_id}

    cond do
      own == [] -> {:error, {:release_contact_not_target_spacecraft, contact.realized_contact_id}}
      members == [] -> {:error, {:command_group_nothing_to_release, contact.realized_contact_id}}
      true -> {:ok, members}
    end
  end

  defp release_member(org, mission, request_id, entry_id, expired, contact, actor, opts) do
    if MapSet.member?(expired, request_id) do
      {:error, {:command_queue_entry_expired, entry_id}}
    else
      Cadence.Commanding.release_command_queue_entry(
        org,
        mission,
        entry_id,
        contact.realized_contact_id,
        actor,
        attempted_at: Keyword.get(opts, :attempted_at, DateTime.utc_now())
      )
    end
  end

  defp served?(org, mission, %CommandRequest{source_endpoint_ref: ref}, contact) do
    case ReleaseTargetGuard.target(org, mission, ref) do
      {:ok, spacecraft_id} ->
        ReleaseTargetGuard.contact(org, mission, spacecraft_id, contact) == :ok

      {:error, _unknown} ->
        false
    end
  end

  # Members past their expiry end `expired` at once, but keep their place in the stack: the
  # release stops at the first one, with the reason the claim gives (an ordered stack's later
  # members never go out without it).
  defp expire(org, mission, members, at) do
    expired =
      org
      |> Cancellation.expire_requests(mission, Enum.map(members, &elem(&1, 0)), at)
      |> MapSet.new()

    if MapSet.size(expired) > 0, do: ScopedReadUpdates.publish(:commanding_changed, org, mission)
    expired
  end

  defp release_members(org, mission, members, expired, contact, actor, opts) do
    initial = %{released_entry_ids: [], stopped: nil, not_attempted_entry_ids: []}

    members
    |> Enum.with_index()
    |> Enum.reduce_while(initial, fn {{request_id, entry_id}, index}, acc ->
      case release_member(org, mission, request_id, entry_id, expired, contact, actor, opts) do
        {:ok, _released} ->
          {:cont, %{acc | released_entry_ids: acc.released_entry_ids ++ [entry_id]}}

        {:error, reason} ->
          rest = members |> Enum.drop(index + 1) |> Enum.map(&elem(&1, 1))

          {:halt,
           %{
             acc
             | stopped: %{
                 command_queue_entry_id: entry_id,
                 command_request_id: request_id,
                 reason: reason
               },
               not_attempted_entry_ids: rest
           }}
      end
    end)
  end

  defp record(org, mission, group_id, %RealizedContact{} = contact, actor, result) do
    GroupStore.append_events([
      %{
        command_group_id: group_id,
        mission_id: mission,
        kind: :released_on_contact,
        actor: actor,
        at: DateTime.utc_now(),
        payload: %{
          "released_by" => actor,
          "realized_contact_id" => contact.realized_contact_id,
          "booked" => is_binary(contact.scheduled_contact_id),
          "released_entry_ids" => result.released_entry_ids,
          "not_attempted_entry_ids" => result.not_attempted_entry_ids,
          "stopped" => encode_stopped(result.stopped, org, mission)
        }
      }
    ])
  end

  defp encode_stopped(nil, _org, _mission), do: nil

  defp encode_stopped(
         %{command_queue_entry_id: entry_id, command_request_id: request_id} = s,
         org,
         mission
       ),
       do: %{
         "command_queue_entry_id" => entry_id,
         "command_request_id" => request_id,
         "reason" => encode_reason(s.reason, org, mission)
       }
end
