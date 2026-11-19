defmodule Cadence.Runtime.JournalAckAfterProjectorRetryTest do
  @moduledoc """
  #71 (b)(i), 11-14: a batch the persistence projector persisted only on a RETRY still acks its
  journal range, so the processing cursor advances (and checkpoints). 39LEY's cursor stayed at 0
  for another reason: a contact's settle or replay stops its runtime without sealing the journal,
  so the final ack wasn't checkpointed (domain's (ii)). This pins that the retry path itself acks.
  """
  use Cadence.UnitCase, async: false

  alias Cadence.ControllableRuntimePersistence
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal

  alias Cadence.Runtime.{
    IngressJournalConsumer,
    IngressPersistenceProjector,
    ProcessedIngressBatch
  }

  alias Cadence.TestSupport.TelemetryPersistencePolicies

  @context [
    mission_id: "mission-retry-ack",
    realized_contact_id: "contact-retry-ack",
    path_id: "path-retry-ack"
  ]

  @tag :tmp_dir
  @tag capture_log: true
  test "a batch persisted by the projector's retry acks its journal range", %{tmp_dir: tmp_dir} do
    id = System.unique_integer([:positive])
    journal = :"retry_ack_journal_#{id}"

    start_supervised!(
      {IngressJournal,
       @context ++
         [
           name: journal,
           provider_binding_id: "provider-retry-ack-#{id}",
           base_path: tmp_dir,
           durability: :sync,
           max_bytes: 1_024 * 1_024,
           segment_bytes: 64 * 1_024,
           checkpoint_interval_ms: 25
         ]}
    )

    assert {:ok, [entry]} =
             IngressJournal.append_stream(journal, <<1, 2, 3, 4>>, DateTime.utc_now(), %{
               mission_id: "mission-retry-ack",
               protocol_family: :tm
             })

    start_supervised!({ControllableRuntimePersistence, owner: self()})
    projector = start_projector!()

    # Stands in for the executor: hands the consumer's evidence, with its completion, to the
    # real projector.
    executor =
      spawn_link(fn -> forward_to_projector(projector) end)

    consumer =
      start_supervised!(
        {IngressJournalConsumer,
         @context ++
           [
             name: :"retry_ack_consumer_#{id}",
             provider_binding_id: "provider-retry-ack-#{id}",
             journal_name: journal,
             executor_name: executor,
             poll_interval_ms: 5
           ]}
      )

    # The first persist fails (39LEY: the archive was backpressured); the projector requeues the
    # batch and retries it on its own, without the consumer doing anything.
    assert_receive {:runtime_persistence_started, ^projector, first, [_], _}, 2_000
    send(projector, {:raise_runtime_persistence, first, RuntimeError.exception("backpressured")})

    assert_receive {:runtime_persistence_started, ^projector, retry, [_], _}, 2_000
    send(projector, {:release_runtime_persistence, retry})

    # The retry's success reaches the consumer, which acks the range: the cursor advances, then
    # the next checkpoint makes it durable.
    assert_eventually(fn ->
      {:ok, snapshot} = IngressJournal.snapshot(journal)

      snapshot.cursors.processing == entry.end_offset and
        snapshot.durable_cursors.processing == entry.end_offset
    end)

    assert {:ok, %{acknowledged_entries: 1}} = IngressJournalConsumer.snapshot(consumer)
  end

  defp forward_to_projector(projector) do
    receive do
      {:"$gen_cast", {:enqueue, {:telemetry, raw_evidence, _async_context, completion}}} ->
        batch =
          ProcessedIngressBatch.new(%{
            mission_id: raw_evidence.mission_id,
            realized_contact_id: "contact-retry-ack",
            path_id: "path-retry-ack",
            provider_binding_id: "provider-retry-ack",
            processing_results: [%{raw_evidence: raw_evidence}],
            completions: [completion]
          })

        :ok = IngressPersistenceProjector.enqueue(projector, batch)
        forward_to_projector(projector)
    end
  end

  defp start_projector! do
    policies = TelemetryPersistencePolicies.postgres()

    start_supervised!(
      {IngressPersistenceProjector,
       mission_id: "mission-retry-ack",
       realized_contact_id: "contact-retry-ack",
       path_id: "path-retry-ack",
       provider_binding_id: "provider-retry-ack",
       profiler: :disabled,
       persistence_policy: policies.persistence,
       current_value_store_policy: policies.current_value_store,
       persistence_module: ControllableRuntimePersistence,
       retry_delay_ms: 1}
    )
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(_fun, 0), do: flunk("condition was not met in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end
end
