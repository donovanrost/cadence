defmodule Cadence.Reads.LimitAlarmConditionsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Auth.Scope
  alias Cadence.Limits
  alias Cadence.Limits.{Definition, DefinitionLifecycle, Store}
  alias Cadence.Reads.LimitAlarmConditions
  @org "org-alarm-owner"
  @mission "mission-alarm-owner"
  @probe Path.expand(
           "../../../../../frontend/modules/limits-and-alarming/src/features/alarm-conditions/producer-consumer-probe.mjs",
           __DIR__
         )
  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "alarm-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    {:ok, _} =
      Limits.persist_limit_definition(
        Definition.new(%{
          mission_id: @mission,
          limit_definition_id: "voltage",
          point_id: "HK.voltage",
          limit_set_name: "FLIGHT",
          version: 1,
          thresholds: %{"yellow_high" => 20, "red_high" => 30}
        }),
        publish_facts?: false
      )

    %{scope: scope}
  end

  test "actual evaluated states reach the public owner with counts, paging and exact evidence",
       c do
    for i <- 1..27 do
      craft =
        TelemetryDecomFixtures.persist_spacecraft!(@org, @mission, display_name: "Vehicle #{i}")

      evaluate(craft.spacecraft_id, "sample-#{i}", 40)
    end

    evaluate(nil, "mission-sample", 10)

    assert {:ok, doc} =
             LimitAlarmConditions.load(c.scope, @mission, %{
               "page" => "2",
               "spacecraft_page" => "2"
             })

    assert doc["states"]["total_count"] == 28
    assert doc["counts"] == %{"critical" => 27, "warning" => 0, "info" => 0, "nominal" => 1}
    assert length(doc["states"]["items"]) == 3
    assert doc["spacecraft"]["total_count"] == 27
    assert length(doc["spacecraft"]["items"]) == 2
    {out, status} = System.cmd("node", [@probe, Jason.encode!(doc)], stderr_to_stdout: true)
    assert status == 0, out
    assert out =~ "CADENCE_ALARM_CONSUMER_OK"

    if directory = System.get_env("CADENCE_ALARM_FIXTURES") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, "alarm-last.json"), Jason.encode!(doc))
    end
  end

  test "state, severity and spacecraft scopes filter before paging without claiming freshness",
       c do
    craft =
      TelemetryDecomFixtures.persist_spacecraft!(@org, @mission, display_name: "Alarm craft")

    evaluate(craft.spacecraft_id, "active-sample", 40)
    evaluate(nil, "nominal-sample", 10)
    assert {:ok, active} = LimitAlarmConditions.load(c.scope, @mission, %{"state" => "active"})
    assert active["states"]["total_count"] == 1
    assert active["counts"]["nominal"] == 0
    assert [%{"sample_id" => "active-sample", "violation" => true}] = active["states"]["items"]

    assert {:ok, nominal} =
             LimitAlarmConditions.load(c.scope, @mission, %{
               "state" => "nominal",
               "spacecraft_id" => "mission"
             })

    assert nominal["states"]["total_count"] == 1

    assert [
             %{
               "spacecraft_id" => nil,
               "sample_id" => "nominal-sample",
               "violation" => false,
               "receipt_time" => receipt_time
             }
           ] = nominal["states"]["items"]

    assert {:ok, received_at, 0} = DateTime.from_iso8601(receipt_time)
    assert DateTime.compare(received_at, ~U[2026-09-08 12:00:00Z]) == :eq

    refute Map.has_key?(nominal, "freshness")
    assert {:ok, empty} = LimitAlarmConditions.load(c.scope, @mission, %{"severity" => "warning"})
    assert empty["states"]["total_count"] == 0
    assert empty["counts"]["critical"] == 1
    assert empty["counts"]["nominal"] == 1
  end

  test "foreign scope, unknown spacecraft and malformed filters are unavailable", c do
    for params <- [
          %{"page" => "0"},
          %{"state" => "acknowledged"},
          %{"severity" => "fatal"},
          %{"document" => "injected"},
          %{"query" => "bad\n"},
          %{"spacecraft_id" => "foreign"}
        ] do
      assert {:error, :unavailable} = LimitAlarmConditions.load(c.scope, @mission, params)
    end

    assert {:error, :unavailable} =
             LimitAlarmConditions.load(%{c.scope | organization_id: "foreign"}, @mission)

    assert {:error, :unavailable} =
             LimitAlarmConditions.load(%{c.scope | mission_id: "foreign"}, @mission)

    assert {:error, :unavailable} =
             LimitAlarmConditions.load(%{c.scope | actor_kind: :service}, @mission)
  end

  defp evaluate(craft, sample, value) do
    source = %{
      mission_id: @mission,
      spacecraft_id: craft,
      point_id: "HK.voltage",
      point_name: "Voltage",
      source_sample_type: :telemetry_sample,
      sample_id: sample,
      value: value,
      generation_time: nil,
      receipt_time: ~U[2026-09-08 12:00:00Z],
      provenance: %{}
    }

    assert {:ok, [event]} =
             Limits.evaluate_source_samples(
               [source],
               DefinitionLifecycle.list_active_definitions(@org, @mission, [])
             )

    assert {:ok, [_]} = Store.persist_latest_states(Cadence.Repo, [event])
  end
end
