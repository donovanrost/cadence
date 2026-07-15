defmodule Cadence.GroundNetworks.CredentialResolver do
  @moduledoc "Narrow credential-reference resolver for provider control-plane requests."

  @type resolver :: (binary() -> {:ok, binary()} | {:error, term()})

  @spec resolver(keyword()) :: resolver()
  def resolver(opts \\ []) do
    case Keyword.get(opts, :credential_resolver) do
      resolver when is_function(resolver, 1) -> resolver
      _other -> &resolve(&1, opts)
    end
  end

  @spec resolve(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def resolve(reference, opts \\ [])

  def resolve("env://" <> variable, _opts) when variable != "" do
    case System.fetch_env(variable) do
      {:ok, value} when value != "" -> {:ok, value}
      _other -> {:error, {:credential_reference_not_found, "env://#{variable}"}}
    end
  end

  def resolve("config://" <> name, _opts) when name != "" do
    credentials = Application.get_env(:cadence, :ground_network_credentials, %{})

    case Map.get(credentials, name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:credential_reference_not_found, "config://#{name}"}}
    end
  end

  def resolve(reference, _opts), do: {:error, {:unsupported_credential_reference, reference}}
end
