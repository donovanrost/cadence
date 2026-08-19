defmodule Cadence.Runtime.IngressPersistenceProjectorTest do
  use Cadence.UnitCase, async: false

  alias Cadence.ControllableRuntimePersistence
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.{IngressPersistenceProjector, ProcessedIngressBatch}

  test "notify_when_below replies immediately when projector queue is below threshold" do
    name = :"ingress_persistence_projector_test_#{System.unique_integer([:positive])}"
    start_projector!(name)

    ref = make_ref()

    assert :ok = IngressPersistenceProjector.notify_when_below(name, 1, self(), ref)

    assert_receive {:ingress_persistence_capacity_available, projector_pid, ^ref, 0}, 100
    assert is_pid(projector_pid)
  end

  test "notify_when_below stores waiters when projector queue is above threshold" do
    name = :"ingress_persistence_projector_test_#{System.unique_integer([:positive])}"
    pid = start_projector!(name)

    :sys.replace_state(pid, &%{&1 | queue_depth: 10})

    ref = make_ref()

    assert :ok = IngressPersistenceProjector.notify_when_below(name, 5, self(), ref)
    refute_receive {:ingress_persistence_capacity_available, ^pid, ^ref, _queue_depth}, 50

    assert {:ok, snapshot} = IngressPersistenceProjector.snapshot(name)
    assert snapshot.capacity_waiter_count == 1
  end

  test "cancel_notify_when_below removes a stored waiter" do
    name = :"ingress_persistence_projector_test_#{System.unique_integer([:positive])}"
    pid = start_projector!(name)
    :sys.replace_state(pid, &%{&1 | queue_depth: 10})

    ref = make_ref()

    assert :ok = IngressPersistenceProjector.notify_when_below(name, 5, self(), ref)
    assert {:ok, waiting_snapshot} = IngressPersistenceProjector.snapshot(name)
    assert waiting_snapshot.capacity_waiter_count == 1

    assert :ok = IngressPersistenceProjector.cancel_notify_when_below(name, ref)

    assert {:ok, canceled_snapshot} = IngressPersistenceProjector.snapshot(name)
    assert canceled_snapshot.capacity_waiter_count == 0
  end

  test "projector notifies waiters when an empty queue pass releases capacity" do
    name = :"ingress_persistence_projector_test_#{System.unique_integer([:positive])}"
    pid = start_projector!(name)
    :sys.replace_state(pid, &%{&1 | queue_depth: 10})

    ref = make_ref()

    assert :ok = IngressPersistenceProjector.notify_when_below(name, 5, self(), ref)

    send(pid, :process_queue)

    assert_receive {:ingress_persistence_capacity_available, ^pid, ^ref, 0}, 100
    assert {:ok, snapshot} = IngressPersistenceProjector.snapshot(name)
    assert snapshot.capacity_waiter_count == 0
  end

  test "quiesce waits for in-flight persistence and rejects later batches" do
    start_supervised!({ControllableRuntimePersistence, owner: self()})

    name = :"ingress_persistence_projector_test_#{System.unique_integer([:positive])}"

    projector =
      start_projector!(name, persistence_module: ControllableRuntimePersistence)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: "mission-ingress-projector",
        source_ref: "test/projector-quiescence",
        raw: <<1, 2, 3>>
      })

    batch =
      ProcessedIngressBatch.new(%{
        mission_id: "mission-ingress-projector",
        realized_contact_id: "contact-ingress-projector",
        path_id: "path-ingress-projector",
        provider_binding_id: "provider-ingress-projector",
        processing_results: [%{raw_evidence: raw_evidence}]
      })

    assert :ok = IngressPersistenceProjector.enqueue(name, batch)

    assert_receive {:runtime_persistence_started, ^projector, release_ref, [_], _},
                   500

    quiesce_task = Task.async(fn -> IngressPersistenceProjector.quiesce(name) end)
    assert Task.yield(quiesce_task, 0) == nil

    send(projector, {:release_runtime_persistence, release_ref})

    assert {:ok,
            %{
              status: :quiesced,
              persisted_count: 1,
              queue_depth: 0
            }} = Task.await(quiesce_task)

    assert [{[_], _}] = ControllableRuntimePersistence.calls()

    assert :ok = IngressPersistenceProjector.enqueue(name, batch)

    assert {:ok,
            %{
              lifecycle_status: :quiesced,
              enqueued_count: 1,
              persisted_count: 1,
              queue_depth: 0
            }} = IngressPersistenceProjector.snapshot(name)
  end

  defp start_projector!(name, opts \\ []) do
    start_supervised!(
      {IngressPersistenceProjector,
       Keyword.merge(
         [
           name: name,
           mission_id: "mission-ingress-projector",
           realized_contact_id: "contact-ingress-projector",
           path_id: "path-ingress-projector",
           provider_binding_id: "provider-ingress-projector"
         ],
         opts
       )}
    )
  end
end
