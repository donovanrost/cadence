defmodule Cadence.RuntimeTestSupportTest do
  @moduledoc "The default RuntimeCase teardown stops contact-settler children before its sandbox closes."
  use Cadence.RuntimeCase, async: false

  alias Cadence.Contacts.ContactSettler
  alias Cadence.RuntimeTestSupport

  test "cleanup stops every child of the default contact-settler supervisor" do
    supervisor = ContactSettler.supervisor_name()
    assert DynamicSupervisor.which_children(supervisor) == []

    {:ok, child} =
      DynamicSupervisor.start_child(
        supervisor,
        Task.child_spec(fn ->
          receive do
            :stop -> :ok
          end
        end)
      )

    ref = Process.monitor(child)

    assert Enum.any?(DynamicSupervisor.which_children(supervisor), fn {_, pid, _, _} ->
             pid == child
           end)

    assert :ok = RuntimeTestSupport.cleanup_default_runtime()
    assert_receive {:DOWN, ^ref, :process, ^child, :shutdown}
    assert DynamicSupervisor.which_children(supervisor) == []
  end
end
