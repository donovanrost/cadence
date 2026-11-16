defmodule Cadence.Commanding.Groups.ExpiryEvent do
  @moduledoc """
  ux U75: a group's `expired` timeline event, once per group, written by whichever path first
  ends its members `expired` (lane dispatch, a named release, the sweep; all go through
  `Cancellation.cancel/5`). `at` is the group's `expires_at`; the actor is Cadence.

  Payload `%{"sent" => n, "not_sent" => m}`: members that went out before the deadline, and those
  that didn't (ended `expired`, or still queued behind another lane and expiring with them: a
  group's members share one `expires_at`, DECISIONS #97). The event id is fixed per group, so a
  second path's insert is a no-op.
  """

  import Ecto.Query

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Commanding.Groups.{CommandGroupEventRow, GroupStore}
  alias Cadence.Repo

  @spec record(binary(), binary(), [map()]) :: :ok
  def record(org, mission, canceled_requests) do
    canceled_requests
    |> Enum.map(& &1.command_group_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&record_group(org, mission, &1))
  end

  defp record_group(org, mission, group_id) do
    case GroupStore.fetch(org, mission, group_id) do
      {:ok, group} ->
        {sent, not_sent} = counts(org, mission, group_id)

        %{
          event_id: "command_group_event_expired_" <> group_id,
          command_group_id: group_id,
          mission_id: mission,
          kind: :expired,
          actor: %{"actor_kind" => "system"},
          at: expires_at(group) || DateTime.utc_now(),
          payload: %{"sent" => sent, "not_sent" => not_sent}
        }
        |> CommandGroupEventRow.changeset()
        |> Repo.insert(on_conflict: :nothing, conflict_target: :event_id)

      _gone ->
        :ok
    end
  end

  defp counts(org, mission, group_id) do
    rows =
      from(r in CommandRequestRow,
        where:
          r.organization_id == ^org and r.mission_id == ^mission and
            r.command_group_id == ^group_id,
        select:
          {r.lifecycle_state,
           fragment("?->'value'->'cancellation'->>'reason'", r.metadata_document)}
      )
      |> Repo.all()

    sent = Enum.count(rows, fn {state, _reason} -> state == "released" end)

    not_sent =
      Enum.count(rows, fn
        {"queued", _reason} -> true
        {"canceled", "expired"} -> true
        _other -> false
      end)

    {sent, not_sent}
  end

  defp expires_at(%{release: %{"expires_at" => %DateTime{} = at}}), do: at

  defp expires_at(%{release: %{"expires_at" => iso}}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp expires_at(_group), do: nil
end
