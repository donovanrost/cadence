defmodule Cadence.Secrets.ResolverConfiguration do
  @moduledoc "Builds immutable resolver options from explicit or application configuration."

  @data_source_option_keys [
    :credential_material_resolver,
    :credential_material_authorizer,
    :credential_secret_backend,
    :env_material_profiles
  ]

  @spec provider_options(keyword()) :: keyword()
  def provider_options(opts \\ []) when is_list(opts) do
    configured =
      Keyword.get_lazy(opts, :provider_credential_configuration, fn ->
        %{
          local: Application.get_env(:cadence, :provider_local_credentials, []),
          credentials: Application.get_env(:cadence, :ground_network_credentials, %{})
        }
      end)

    defaults = [
      allow_local_provider_credentials?:
        configured |> config_value(:local, []) |> config_value(:enabled, false),
      ground_network_credentials: config_value(configured, :credentials, %{})
    ]

    Keyword.merge(defaults, opts)
  end

  @spec data_source_options(keyword()) :: keyword()
  def data_source_options(opts \\ []) when is_list(opts) do
    configured =
      Keyword.get_lazy(opts, :credential_configuration, fn ->
        Application.get_env(:cadence, :data_source_credentials, [])
      end)

    defaults =
      [
        credential_material_resolver: config_value(configured, :material_resolver),
        credential_material_authorizer: config_value(configured, :material_authorizer),
        credential_secret_backend: config_value(configured, :secret_backend),
        env_material_profiles: config_value(configured, :env_material_profiles)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    Keyword.merge(defaults, opts)
  end

  @spec data_source_configured?(keyword()) :: boolean()
  def data_source_configured?(opts) when is_list(opts) do
    opts
    |> data_source_options()
    |> Keyword.take(@data_source_option_keys ++ [:secret_backend])
    |> Keyword.values()
    |> Enum.any?(&(not is_nil(&1)))
  end

  defp config_value(config, key, default \\ nil)

  defp config_value(config, key, default) when is_list(config),
    do: Keyword.get(config, key, default)

  defp config_value(config, key, default) when is_map(config),
    do: Map.get(config, key, Map.get(config, Atom.to_string(key), default))

  defp config_value(_config, _key, default), do: default
end
