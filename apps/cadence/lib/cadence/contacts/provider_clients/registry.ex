defmodule Cadence.Contacts.ProviderClients.Registry do
  @moduledoc """
  Compile-time registry for ground-station provider control-plane clients.

  A future plugin system can replace or extend this registry without changing
  the provider-client behaviour or booking workflow.
  """

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.Contacts.ProviderProfile

  @clients %{
    "simulator_http" => SimulatorHTTP
  }

  @spec fetch(ProviderProfile.t()) :: {:ok, module()} | {:error, term()}
  def fetch(%ProviderProfile{configuration: configuration}) do
    scheduling =
      Map.get(configuration, "scheduling", Map.get(configuration, :scheduling, %{}))

    client_key = Map.get(scheduling, "client", Map.get(scheduling, :client))

    case Map.fetch(@clients, normalize_key(client_key)) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_provider_client, client_key}}
    end
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
