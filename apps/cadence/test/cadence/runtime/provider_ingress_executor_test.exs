defmodule Cadence.Runtime.ProviderIngressExecutorTest do
  use ExUnit.Case, async: true

  alias Cadence.Runtime.{IngressPersistenceProjector, ProviderIngressExecutor}

  test "notify_when_below replies immediately when executor queue is below threshold" do
    name = :"provider_ingress_executor_test_#{System.unique_integer([:positive])}"

    start_executor!(name)

    ref = make_ref()

    assert :ok = ProviderIngressExecutor.notify_when_below(name, 1, self(), ref)

    assert_receive {:provider_ingress_capacity_available, executor_pid, ^ref, 0}, 100
    assert is_pid(executor_pid)
  end

  test "notify_when_below stores waiters when executor queue is above threshold" do
    name = :"provider_ingress_executor_test_#{System.unique_integer([:positive])}"

    pid = start_executor!(name)

    :sys.replace_state(pid, &%{&1 | queue_depth: 10})

    ref = make_ref()

    assert :ok = ProviderIngressExecutor.notify_when_below(name, 5, self(), ref)
    refute_receive {:provider_ingress_capacity_available, ^pid, ^ref, _queue_depth}, 50

    assert {:ok, snapshot} = ProviderIngressExecutor.snapshot(name)
    assert snapshot.capacity_waiter_count == 1
  end

  test "cancel_notify_when_below removes a stored waiter" do
    name = :"provider_ingress_executor_test_#{System.unique_integer([:positive])}"
    pid = start_executor!(name)
    :sys.replace_state(pid, &%{&1 | queue_depth: 10})

    ref = make_ref()

    assert :ok = ProviderIngressExecutor.notify_when_below(name, 5, self(), ref)
    assert {:ok, waiting_snapshot} = ProviderIngressExecutor.snapshot(name)
    assert waiting_snapshot.capacity_waiter_count == 1

    assert :ok = ProviderIngressExecutor.cancel_notify_when_below(name, ref)

    assert {:ok, canceled_snapshot} = ProviderIngressExecutor.snapshot(name)
    assert canceled_snapshot.capacity_waiter_count == 0
  end

  test "executor waits on projector capacity notification when projector is backpressured" do
    projector_name = :"ingress_projector_for_executor_test_#{System.unique_integer([:positive])}"
    projector_pid = start_projector!(projector_name)

    executor_name = :"provider_ingress_executor_test_#{System.unique_integer([:positive])}"
    executor_pid = start_executor!(executor_name, persistence_projector_name: projector_name)

    :sys.replace_state(projector_pid, &%{&1 | queue_depth: 9_000})

    send(executor_pid, :process_queue)

    assert eventually(fn ->
             {:ok, executor_snapshot} = ProviderIngressExecutor.snapshot(executor_name)

             executor_snapshot.projector_backpressured? and
               executor_snapshot.projector_capacity_waiting?
           end)

    assert {:ok, projector_snapshot} = IngressPersistenceProjector.snapshot(projector_name)
    assert projector_snapshot.capacity_waiter_count == 1

    send(projector_pid, :process_queue)

    assert eventually(fn ->
             {:ok, executor_snapshot} = ProviderIngressExecutor.snapshot(executor_name)

             not executor_snapshot.projector_backpressured? and
               not executor_snapshot.projector_capacity_waiting?
           end)
  end

  defp start_executor!(name, opts \\ []) do
    start_supervised!(
      {ProviderIngressExecutor,
       Keyword.merge(
         [
           name: name,
           mission_id: "mission-ingress-executor",
           realized_contact_id: "contact-ingress-executor",
           path_id: "path-ingress-executor",
           provider_binding_id: "provider-ingress-executor",
           persistence_projector_name: :missing_projector
         ],
         opts
       )}
    )
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

  defp eventually(fun, attempts_left \\ 20)

  defp eventually(fun, attempts_left) when attempts_left > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts_left - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
