defmodule Cadence.Reads.MissionRuntimeAttention do
  @moduledoc """
  The `mission_runtime` source of the mission attention read (2026-11-12 outage; ux U38): the
  mission's active generation isn't applied, so no spacecraft's telemetry is processed.
  Derived from `Cadence.Reads.MissionRuntimeStatus` (same record and reasons as `/counts`
  `runtime`), open once that reads `not_applied` (after its 60 s debounce). P1, nothing to
  acknowledge; it resolves (`resolved_by` kind `system`, action `applied`) when the runtime
  applies a generation again. One item per mission, id = the mission id. U91 adds
  `reason_detail` (what a spec mismatch failed to verify) and `next_pass` (the pass in progress,
  else the next within 2 h; `Reads.MissionRuntimeAttention.NextPass`).
  """

  alias Cadence.Reads.MissionRuntimeAttention.NextPass
  alias Cadence.Reads.MissionRuntimeStatus

  @source "mission_runtime"
  @resolved_window_s 60

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    case MissionRuntimeStatus.status(org, mission) do
      %{state: "not_applied"} = status -> [item(org, mission, status)]
      _applied_or_unknown -> []
    end
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    case MissionRuntimeStatus.status(org, mission) do
      %{state: "applied", recovered_at: %DateTime{} = at} ->
        if DateTime.compare(at, since) != :lt and
             DateTime.diff(DateTime.utc_now(), at) <= @resolved_window_s,
           do: [
             %{
               id: mission,
               source: @source,
               resolved_by: %{"kind" => "system"},
               action: "applied",
               resolved_at: at
             }
           ],
           else: []

      _other ->
        []
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission) do
    # From the status alone: the item's next_pass is a query, not needed for a count.
    open =
      if match?(%{state: "not_applied"}, MissionRuntimeStatus.status(org, mission)),
        do: 1,
        else: 0

    %{open: open, acknowledged: 0}
  end

  defp item(org, mission, status) do
    %{
      id: mission,
      source: @source,
      conflict: "generation_not_applied",
      state: "open",
      reason: status.reason,
      failure_message: status.failure_message,
      # U91: the field a spec mismatch failed to verify (opaque, Technical details), and the
      # pass this costs.
      reason_detail: MissionRuntimeStatus.reason_detail(org, mission),
      next_pass: NextPass.for_mission(org, mission, DateTime.utc_now()),
      desired_generation: status.desired_generation,
      applied_generation: status.applied_generation,
      since: status.since,
      activated_at: status.activated_at,
      change_set_id: status.change_set_id,
      raised_at: status.since,
      spacecraft_id: nil,
      contact_id: nil,
      provider_reservation_id: nil,
      ground_station_ref: nil,
      provider_id: nil,
      starts_at: nil,
      acknowledged_by: nil,
      provider_message: nil,
      resolution: nil
    }
  end
end
