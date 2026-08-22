defmodule Cadence.ProviderAdapters.Registry do
  @moduledoc """
  Registry of first-party provider adapters available to the Cadence runtime.
  """

  alias Cadence.ProviderAdapters.TCPSocket

  @type t :: %{required(atom()) => module()}

  @spec default() :: t()
  def default do
    %{
      tcp_socket: TCPSocket
    }
  end

  @spec fetch_module(atom()) :: {:ok, module()} | {:error, term()}
  def fetch_module(adapter_key) when is_atom(adapter_key) do
    case Map.fetch(default(), adapter_key) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_provider_adapter, adapter_key}}
    end
  end
end
