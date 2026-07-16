defmodule Cadence.Contacts.ProviderClientContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Contacts.ProviderClient
  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.TestSupport.FakeProviderClient

  test "the simulator and fake implement the provider control-plane contract" do
    callbacks = ProviderClient.behaviour_info(:callbacks)
    assert Code.ensure_loaded?(SimulatorHTTP)
    assert Code.ensure_loaded?(FakeProviderClient)

    for {name, arity} <- callbacks do
      assert function_exported?(SimulatorHTTP, name, arity)
      assert function_exported?(FakeProviderClient, name, arity)
    end
  end

  test "fake modification behavior is request-local rather than process-global" do
    parent = self()

    first_opts = [on_modify: &send(parent, {:first, &1})]
    second_opts = [on_modify: &send(parent, {:second, &1})]
    attrs = %{"client_reference" => "change-one", "expected_revision" => 1}

    assert {:ok, _contact} =
             FakeProviderClient.modify_contact(nil, "contact-one", attrs, first_opts)

    assert {:ok, _contact} =
             FakeProviderClient.modify_contact(nil, "contact-two", attrs, second_opts)

    assert_received {:first, %{provider_contact_id: "contact-one"}}
    assert_received {:second, %{provider_contact_id: "contact-two"}}
    refute_received {:first, %{provider_contact_id: "contact-two"}}
    refute_received {:second, %{provider_contact_id: "contact-one"}}
  end
end
