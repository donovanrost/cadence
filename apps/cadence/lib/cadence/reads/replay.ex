defmodule Cadence.Reads.Replay do
  @moduledoc "Read-side facade for replay runs and replay outputs."

  alias Cadence.Control.Replay.Store

  defdelegate list_runs(organization_id, mission_id, opts \\ []), to: Store
  defdelegate fetch_run(replay_run_id), to: Store
  defdelegate telemetry_samples(replay_run_id, opts \\ []), to: Store
  defdelegate managed_capability_records(replay_run_id, opts \\ []), to: Store
  defdelegate managed_action_requests(replay_run_id, opts \\ []), to: Store
  defdelegate managed_timer_events(replay_run_id, opts \\ []), to: Store
end
