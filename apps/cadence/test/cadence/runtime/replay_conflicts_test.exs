defmodule Cadence.Runtime.ReplayConflictsTest do
  # #99 follow-up: the tripped unit's durable record (director GO 11-17; lead's build notes).
  use Cadence.ProcessDataCase

  import ExUnit.CaptureLog

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.{IngressPersistenceProjector, ProcessedIngressBatch}
  alias Cadence.Runtime.ReplayConflicts.{Recorder, Row}
  alias Cadence.TestSupport.TelemetryPersistencePolicies

  @mission "mission-replay-conflicts"

  defmodule RollingBackPersistence do
    @moduledoc false
    # Persists the way #99's writers fail: a real transaction that writes, hits the tripwire and
    # rolls back. `:ok` once the test says the fix is in.
    use Agent

    def start_link(_opts), do: Agent.start_link(fn -> :conflict end, name: __MODULE__)
    def fix, do: Agent.update(__MODULE__, fn _ -> :ok end)

    def persist_semantic_processing_results(_results, _opts) do
      case Agent.get(__MODULE__, & &1) do
        :ok ->
          :ok

        :conflict ->
          Repo.transaction(fn ->
            Repo.insert_all("partition_stream_keys", [
              %{mission_id: "mission-replay-conflicts", partition_id: "p", stream_key: "doomed"}
            ])

            Repo.rollback({:replay_id_conflict, :alarm_episode, "aep_conflict"})
          end)
      end
    end
  end

  defp unit(path \\ :storage),
    do: Recorder.stream_unit(path, @mission, "contact-1", "path-1", "binding-1")

  defp rows, do: Repo.all(from(row in Row, order_by: [asc: row.inserted_at]))
  defp open_rows, do: Enum.filter(rows(), &is_nil(&1.resolved_at))
  defp conflict(id \\ "aep_1"), do: {:error, {:replay_id_conflict, :alarm_episode, id}}

  test "finds the conflict however a caller wraps it" do
    wrapped =
      {:error,
       {:semantic_runtime_failed, %{causes: [{:replay_id_conflict, :alarm_event, "aev_1"}]}}}

    assert Recorder.conflict(wrapped) == {:alarm_event, "aev_1"}
    assert Recorder.conflict({:error, :bad_frame}) == nil
    assert Recorder.track({:error, :bad_frame}, unit(), :clear) == :clear
    assert rows() == []
  end

  test "the record survives the failing transaction's rollback" do
    result =
      Repo.transaction(fn ->
        Repo.insert_all("partition_stream_keys", [
          %{mission_id: @mission, partition_id: "p", stream_key: "doomed"}
        ])

        Repo.rollback({:replay_id_conflict, :alarm_episode, "aep_1"})
      end)

    assert result == conflict()
    assert Recorder.track(result, unit(), :unknown) == :open

    assert Repo.aggregate(
             from(key in "partition_stream_keys", where: key.stream_key == "doomed"),
             :count
           ) == 0

    assert [
             %Row{
               path: "storage",
               effect_kind: "alarm_episode",
               effect_id: "aep_1",
               conflict_count: 1
             }
           ] =
             open_rows()
  end

  test "opening is idempotent: a re-trip, even after a lost process, bumps the one open record" do
    assert Recorder.track(conflict(), unit(), :clear) == :open
    # The process crashed before its next success: a fresh one starts :unknown and trips again.
    assert Recorder.track(conflict(), unit(), :unknown) == :open

    assert [%Row{conflict_count: 2} = row] = open_rows()
    assert DateTime.compare(row.last_conflict_at, row.first_seen_at) == :gt

    # The other path of the same stream is its own unit.
    assert Recorder.track(conflict(), unit(:processing), :clear) == :open
    assert length(open_rows()) == 2
  end

  test "the unit's next commit resolves it, and a later trip opens a new record" do
    assert Recorder.track(conflict(), unit(), :clear) == :open
    assert Recorder.track(:ok, unit(), :open) == :clear
    assert open_rows() == []
    assert [%Row{resolved_at: %DateTime{}}] = rows()

    assert Recorder.track(conflict(), unit(), :clear) == :open
    assert [%Row{conflict_count: 1}] = open_rows()
    assert length(rows()) == 2
  end

  test "a success with nothing open writes nothing" do
    assert Recorder.track(:ok, unit(), :unknown) == :clear
    assert Recorder.track({:ok, :inserted}, unit(), :clear) == :clear
    assert rows() == []
  end

  test "a failed record write is logged and changes nothing for the caller" do
    bad_unit = %{unit() | mission_id: 123}

    log =
      capture_log(fn ->
        assert Recorder.track(conflict(), bad_unit, :clear) == :open
      end)

    assert log =~ "MM_REPLAY_ID_CONFLICT record record failed"
    assert log =~ "the next retry writes it"
    assert rows() == []

    # The next retry, with the write working again, opens it.
    assert Recorder.track(conflict(), unit(), :open) == :open
    assert [%Row{conflict_count: 1}] = open_rows()
  end

  test "each recorded conflict counts once on the metric event" do
    ref = make_ref()
    test = self()
    handler = "replay-conflict-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:cadence, :replay_id, :conflict],
      fn _event, measurements, meta, _ ->
        send(test, {ref, measurements, meta})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    Recorder.track(conflict(), unit(), :clear)

    assert_receive {^ref, %{count: 1},
                    %{kind: :alarm_episode, path: :storage, mission_id: @mission}}
  end

  test "the storage path: the projector's rolled-back batch leaves an open record, its retry resolves it" do
    start_supervised!(RollingBackPersistence)
    policies = TelemetryPersistencePolicies.postgres()
    name = :"replay_conflict_projector_#{System.unique_integer([:positive])}"

    start_supervised!(
      {IngressPersistenceProjector,
       name: name,
       mission_id: @mission,
       realized_contact_id: "contact-1",
       path_id: "path-1",
       provider_binding_id: "binding-1",
       profiler: :disabled,
       persistence_module: RollingBackPersistence,
       persistence_policy: policies.persistence,
       current_value_store_policy: policies.current_value_store,
       retry_delay_ms: 20,
       retry_max_ms: 40}
    )

    raw = RawEvidence.new(%{mission_id: @mission, source_ref: "test/replay-conflict", raw: <<1>>})

    batch =
      ProcessedIngressBatch.new(%{
        mission_id: @mission,
        realized_contact_id: "contact-1",
        path_id: "path-1",
        provider_binding_id: "binding-1",
        processing_results: [%{raw_evidence: raw}]
      })

    capture_log(fn ->
      assert :ok = IngressPersistenceProjector.enqueue(name, batch)

      assert_eventually(fn ->
        assert [%Row{conflict_count: count}] = open_rows()
        assert count >= 2
      end)
    end)

    assert [
             %Row{
               path: "storage",
               effect_id: "aep_conflict",
               stream_key: "contact-1:path-1:binding-1"
             }
           ] =
             open_rows()

    assert Repo.aggregate(
             from(key in "partition_stream_keys", where: key.stream_key == "doomed"),
             :count
           ) == 0

    RollingBackPersistence.fix()
    assert_eventually(fn -> assert open_rows() == [] end)
    assert [%Row{resolved_at: %DateTime{}}] = rows()
  end

  defp assert_eventually(assertion, attempts \\ 50) do
    assertion.()
  rescue
    error in [ExUnit.AssertionError, MatchError] ->
      if attempts > 1 do
        Process.sleep(20)
        assert_eventually(assertion, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
