defmodule Cadence.Runtime.IngressPersistenceProjectorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Runtime.IngressPersistenceProjector

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

  defp start_projector!(name) do
    start_supervised!(
      {IngressPersistenceProjector,
       name: name,
       mission_id: "mission-ingress-projector",
       realized_contact_id: "contact-ingress-projector",
       path_id: "path-ingress-projector",
       provider_binding_id: "provider-ingress-projector"}
    )
  end
end
