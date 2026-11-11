defmodule Cadence.Control.UplinkReadiness.Attention do
  @moduledoc """
  The `uplink_blocked` source of the mission attention read (#54/#58): a live pass whose uplink
  is blocked while command groups wait on its spacecraft. Open only (nothing to acknowledge);
  it resolves when the uplink recovers or the pass ends (`resolved_by` kind `system`).
  """

  alias Cadence.Commanding.Groups.Waiting
  alias Cadence.Control.UplinkReadiness
  alias Cadence.Control.UplinkReadiness.Groups

  @source "uplink_blocked"

  def source, do: @source

  @spec items(binary(), binary(), atom()) :: [map()]
  def items(org, mission, table \\ UplinkReadiness.table()) do
    blocked =
      org
      |> UplinkReadiness.live(mission, table)
      |> Enum.filter(&(&1.state == :blocked))

    if blocked == [] do
      []
    else
      endpoints = endpoints_by_spacecraft(org, mission)

      for entry <- Enum.sort_by(blocked, & &1.starts_at, DateTime),
          groups = Waiting.queued_on(org, mission, Map.get(endpoints, entry.spacecraft_id, [])),
          groups != [] do
        item(entry, groups)
      end
    end
  end

  @spec resolved_since(binary(), binary(), DateTime.t(), atom()) :: [map()]
  def resolved_since(org, mission, since, table \\ UplinkReadiness.table()) do
    org
    |> UplinkReadiness.resolved_since(mission, since, table)
    |> Enum.map(fn entry ->
      %{
        id: entry.scheduled_contact_id,
        source: @source,
        resolved_by: %{"kind" => "system"},
        action: entry.action,
        resolved_at: entry.resolved_at
      }
    end)
  end

  @spec counts(binary(), binary(), atom()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission, table \\ UplinkReadiness.table()),
    do: %{open: length(items(org, mission, table)), acknowledged: 0}

  defp item(entry, group_ids) do
    %{
      id: entry.scheduled_contact_id,
      source: @source,
      state: "open",
      reason: reason_key(entry.reason),
      spacecraft_id: entry.spacecraft_id,
      contact_id: entry.scheduled_contact_id,
      provider_reservation_id: entry.provider_reservation_id,
      provider_contact_ref: entry.provider_contact_ref,
      ground_station_ref: entry.ground_station_ref,
      provider_id: entry.provider_id,
      starts_at: entry.starts_at,
      ends_at: entry.ends_at,
      raised_at: entry.since,
      command_group_ids: group_ids
    }
  end

  # qa #41: a recorded reason can be a provider error struct, not only an atom.
  defp reason_key(nil), do: nil
  defp reason_key(reason) when is_atom(reason) or is_binary(reason), do: to_string(reason)

  defp reason_key(%{category: category}) when is_atom(category) and not is_nil(category),
    do: "provider_" <> Atom.to_string(category)

  defp reason_key({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_key(_other), do: "unknown"

  defp endpoints_by_spacecraft(org, mission) do
    org
    |> Groups.spacecraft_by_endpoint(mission)
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
  end
end
