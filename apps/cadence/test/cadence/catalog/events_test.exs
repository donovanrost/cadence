defmodule Cadence.Catalog.EventsTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Events
  alias Cadence.Catalog.ImportRun

  defp run(overrides) do
    ImportRun.new(
      Map.merge(
        %{
          mission_id: "mission_abc",
          artifact_id: "catalog_artifact_xyz",
          catalog_family: :combined,
          importer_key: "cadence_yaml"
        },
        overrides
      )
    )
  end

  describe "topic names" do
    test "import_runs_topic is mission-scoped" do
      assert Events.import_runs_topic("mission_abc") ==
               "catalog:mission:mission_abc:import_runs"
    end

    test "import_run_topic is run-scoped" do
      assert Events.import_run_topic("mission_abc", "catalog_import_run_123") ==
               "catalog:mission:mission_abc:import_run:catalog_import_run_123"
    end
  end

  describe "broadcast_started/1" do
    test "publishes to the mission and run topics" do
      run = run(%{status: :running})
      :ok = Events.subscribe_import_runs(run.mission_id)
      :ok = Events.subscribe_import_run(run.mission_id, run.import_run_id)

      assert :ok = Events.broadcast_started(run)

      assert_receive {:import_run_started, ^run}
      assert_receive {:import_run_started, ^run}
    end
  end

  describe "broadcast_completed/1" do
    test "publishes completed event" do
      run = run(%{status: :completed, completed_at: DateTime.utc_now()})
      :ok = Events.subscribe_import_run(run.mission_id, run.import_run_id)

      assert :ok = Events.broadcast_completed(run)
      assert_receive {:import_run_completed, ^run}
    end
  end

  describe "broadcast_failed/1" do
    test "publishes failed event" do
      run = run(%{status: :failed, failure_reason: {:exception, "boom"}})
      :ok = Events.subscribe_import_runs(run.mission_id)

      assert :ok = Events.broadcast_failed(run)
      assert_receive {:import_run_failed, ^run}
    end
  end

  describe "broadcast_updated/1" do
    test "publishes updated event on non-terminal transitions" do
      run = run(%{status: :running})
      :ok = Events.subscribe_import_run(run.mission_id, run.import_run_id)

      assert :ok = Events.broadcast_updated(run)
      assert_receive {:import_run_updated, ^run}
    end
  end
end
