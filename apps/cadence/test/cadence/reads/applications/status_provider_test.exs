defmodule Cadence.Reads.Applications.StatusProviderTest do
  use ExUnit.Case, async: true
  alias Cadence.Applications.Status
  alias Cadence.Reads.Applications.StatusProvider

  test "only bounded host-standard status data crosses the provider boundary" do
    status = %Status{state: :configured, label: "Configured", tone: :ready}
    assert {:ok, ^status} = StatusProvider.invoke(__MODULE__, nil, {:return, {:ok, status}})

    for invalid <- [
          %{status | tone: :invented},
          %{status | label: String.duplicate("x", 4097)},
          %{status | label: <<255>>},
          %{status | facts: [%{id: "fact", label: "Fact", value: %{secret: true}}]},
          %{status | facts: List.duplicate(%{id: "fact", label: "Fact", value: "1"}, 65)},
          %{status | outstanding_actions: [nil]},
          %{},
          nil
        ] do
      assert {:error, :invalid_application_status} =
               StatusProvider.invoke(__MODULE__, nil, {:return, {:ok, invalid}})
    end
  end

  test "provider exceptions, throws, exits and error payloads are contained and sanitized" do
    for context <- [:raise, :throw, :exit, {:return, {:error, "private details"}}, {:return, nil}] do
      assert {:error, :application_status_unavailable} =
               StatusProvider.invoke(__MODULE__, nil, context)
    end
  end

  def load(_scope, :raise), do: raise("private details")
  def load(_scope, :throw), do: throw("private details")
  def load(_scope, :exit), do: exit("private details")
  def load(_scope, {:return, result}), do: result
end
