defmodule Cadence.Control.MissionRuntimeReconciler.AdmissionLog do
  @moduledoc """
  What the reconciler says about admission (11-17 calibration incident; lead, director, U91): the
  mission's runtime failed to admit its generation for minutes, retrying every 30 s, with nothing
  logged. Now, comparing the state before and after a reconcile:

  - a WARNING when admission starts failing, and again when the reason (or its detail) changes,
    naming the mission, the generation and the reason code, e.g. `spec_mismatch
    (binding_set_content_sha256)`: that one word was 11-17's whole diagnosis;
  - an INFO once when it recovers;
  - nothing on the 30 s retries of the same failure.
  """

  require Logger

  alias Cadence.Control.MissionRuntimeStatus

  @spec transition(map(), map()) :: :ok
  def transition(%{failing_since: nil}, %{failing_since: %DateTime{}} = next),
    do: warn(next, "not admitted")

  def transition(%{failing_since: %DateTime{}} = before, %{failing_since: %DateTime{}} = next) do
    if MissionRuntimeStatus.describe(before.last_error) !=
         MissionRuntimeStatus.describe(next.last_error),
       do: warn(next, "still not admitted, for a new reason"),
       else: :ok
  end

  def transition(
        %{failing_since: %DateTime{} = since},
        %{failing_since: nil, last_error: nil, applied_generation: generation} = next
      )
      when is_integer(generation) do
    Logger.info(
      "Mission runtime for #{next.mission_id} admitted generation #{generation} after " <>
        "#{DateTime.diff(DateTime.utc_now(), since)} s of failing",
      mission_id: next.mission_id
    )
  end

  def transition(_before, _next), do: :ok

  defp warn(state, what) do
    %{reason: reason, reason_detail: detail} = MissionRuntimeStatus.describe(state.last_error)
    reason_text = if detail, do: "#{reason} (#{detail})", else: reason
    desired = state.desired_generation || "?"
    applied = state.applied_generation || "none"
    since = DateTime.to_iso8601(state.failing_since)
    retry_s = div(Map.get(state, :safety_poll_interval_ms, 30_000), 1000)

    Logger.warning(
      "Mission runtime for #{state.mission_id} #{what}: generation #{desired} " <>
        "(applied #{applied}), reason #{reason_text}, since #{since}; retrying every #{retry_s} s",
      mission_id: state.mission_id
    )
  end
end
