defmodule Cadence.Platform.AsyncFactDeliveryTest do
  @moduledoc """
  The ingest → verifier and ingest → limits fact flows under ASYNC delivery, production's
  default (`EventBus` delivery `:async`). config/test.exs delivers synchronously for the bulk of
  the suite (director 11-14: keep `:sync` there), so these are the tests that exercise the cast
  path: the data plane never waits on a busy consumer, and nothing is lost or reordered.
  """
  use Cadence.DataCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Control.RuntimeFactConsumer, as: ControlRuntimeFactConsumer
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.{TelemetryFactConsumer, TelemetryLatestValues}
  alias Cadence.Runtime.ProcessingResultsPersisted
  alias Cadence.Telemetry.ObservationIdentitySelectionChanged

  @facts 20

  test "ingest → verifiers: publishing doesn't wait on a busy consumer, and every batch is evaluated in order" do
    owner = self()
    bus = start_bus!(:verifier_bus)

    start_supervised!({ControlRuntimeFactConsumer,
     name: __MODULE__.ControlRuntime,
     event_bus: bus,
     evaluate_telemetry: fn samples ->
       send(owner, {:evaluating, self(), samples})

       # The first batch holds the consumer, as a slow verifier evaluation would.
       if samples == [%{sample_id: "sample-1"}] do
         receive do
           :release -> :ok
         after
           5_000 -> :ok
         end
       end

       send(owner, {:evaluated, samples})
     end,
     evaluate_transport: fn _records, _requests -> :ok end})

    publish_batch!(bus, 1)
    assert_receive {:evaluating, consumer, [%{sample_id: "sample-1"}]}, 1_000

    # The consumer is busy; the publisher (the data plane) carries on regardless.
    started = System.monotonic_time(:millisecond)
    for i <- 2..@facts, do: publish_batch!(bus, i)
    assert System.monotonic_time(:millisecond) - started < 1_000

    send(consumer, :release)

    for i <- 1..@facts do
      sample_id = "sample-#{i}"
      assert_receive {:evaluated, [%{sample_id: ^sample_id}]}, 2_000
    end

    refute_received {:evaluated, _late}
  end

  test "ingest → latest values (limits): every selection change refreshes, in order, past a failure" do
    owner = self()
    bus = start_bus!(:telemetry_bus)

    start_supervised!(
      {TelemetryFactConsumer,
       name: __MODULE__.Telemetry,
       event_bus: bus,
       refresh_point: fn mission_id, point_id, _opts ->
         send(owner, {:refreshed, mission_id, point_id})
         if point_id == "HK.5", do: {:error, :storage_unavailable}, else: {:ok, nil}
       end}
    )

    log =
      capture_log(fn ->
        for i <- 1..@facts, do: publish_selection!(bus, "mission-async", "HK.#{i}")

        for i <- 1..@facts do
          point_id = "HK.#{i}"
          assert_receive {:refreshed, "mission-async", ^point_id}, 2_000
        end
      end)

    # The failed refresh is logged, and the consumer kept going.
    assert log =~ "latest-value projection refresh failed"
    assert Process.alive?(Process.whereis(__MODULE__.Telemetry))
  end

  test "an async consumer reaches the database through the bus's sandbox hook" do
    bus =
      start_bus!(:db_bus, before_notify: {Ecto.Adapters.SQL.Sandbox, :allow, [Cadence.Repo]})

    owner = self()

    start_supervised!(
      {TelemetryFactConsumer,
       name: __MODULE__.TelemetryDb,
       event_bus: bus,
       refresh_point: fn mission_id, point_id, opts ->
         result =
           TelemetryLatestValues.refresh_point(mission_id, point_id, opts)

         send(owner, {:refreshed_from_db, result})
         result
       end}
    )

    publish_selection!(bus, "mission-async-db", "HK.mode")
    assert_receive {:refreshed_from_db, {:ok, nil}}, 2_000
  end

  defp start_bus!(id, opts \\ []) do
    name = Module.concat(__MODULE__, id)

    start_supervised!(%{
      id: {__MODULE__, id},
      start:
        {EventBus, :start_link,
         [[name: name, delivery: :async, before_notify: Keyword.get(opts, :before_notify)]]}
    })

    name
  end

  defp publish_batch!(bus, i) do
    assert :ok =
             Cadence.Runtime.Facts.publish(bus, %ProcessingResultsPersisted{
               batch_id: "batch-#{i}",
               evidence_ids: [],
               telemetry_samples: [%{sample_id: "sample-#{i}"}],
               persisted_at: DateTime.utc_now()
             })
  end

  defp publish_selection!(bus, mission_id, point_id) do
    assert :ok =
             Cadence.Telemetry.Facts.publish(bus, %ObservationIdentitySelectionChanged{
               observation_identity_id: "observation-#{point_id}",
               organization_id: "organization-async",
               mission_id: mission_id,
               point_id: point_id,
               spacecraft_id: "spacecraft-async",
               realm: :flight,
               replay_run_id: nil,
               data_source_id: "source-async",
               binding_id: "binding-async",
               committed_at: DateTime.utc_now()
             })
  end
end
