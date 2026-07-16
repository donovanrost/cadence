defmodule Cadence.Contacts.ProviderClients.Registry do
  @moduledoc "Compile-time registry for provider control-plane clients."

  alias Cadence.Contacts.ProviderClients.SimulatorHTTP
  alias Cadence.GroundNetworks.ProviderContext

  @clients %{"simulator_http" => SimulatorHTTP}

  @spec fetch(ProviderContext.t()) :: {:ok, module()} | {:error, term()}
  def fetch(%ProviderContext{client_key: client_key}) do
    case Map.fetch(@clients, client_key) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_provider_client, client_key}}
    end
  end

  @spec fetch_webhook_authenticator(atom()) :: {:ok, module()} | {:error, term()}
  def fetch_webhook_authenticator(provider_type) when is_atom(provider_type),
    do: {:error, :provider_webhook_authenticator_not_configured}
end
