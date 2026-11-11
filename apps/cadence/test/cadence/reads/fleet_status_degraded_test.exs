defmodule Cadence.Reads.FleetStatusDegradedTest do
  @moduledoc "fe-ops: a slow durable history store degrades the fleet read instead of holding it."
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures
  alias Cadence.Reads.FleetStatus

  setup do
    previous = Application.get_env(:cadence, :fleet_durable_receipts_timeout_ms)
    on_exit(fn -> Application.put_env(:cadence, :fleet_durable_receipts_timeout_ms, previous) end)
    CommandReviewFixtures.scope!()
  end

  test "the read still answers, flagged degraded, when the durable store doesn't answer in time",
       c do
    Application.put_env(:cadence, :fleet_durable_receipts_timeout_ms, 0)
    assert %{telemetry: :degraded, spacecraft: _} = FleetStatus.load(c.org, c.mission)
    assert FleetStatus.last_received_by_spacecraft(c.org, c.mission) == %{}
  end

  test "a store that answers gives telemetry ok", c do
    Application.put_env(:cadence, :fleet_durable_receipts_timeout_ms, 5_000)
    assert %{telemetry: :ok} = FleetStatus.load(c.org, c.mission)
  end
end
