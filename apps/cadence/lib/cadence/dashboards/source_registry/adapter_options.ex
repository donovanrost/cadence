defmodule Cadence.Dashboards.SourceRegistry.AdapterOptions do
  @moduledoc """
  Builds source-adapter options and resolves credential-safe connection context.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ResolvedSourceBinding}

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.Reads.DataSources, as: DataSourceReads

  alias Cadence.DataSources.{DataSource, ResolvedSourceCredential, SourceCredentialMaterial}

  @spec build(
          PlannedSourceRequest.t(),
          ResolvedSourceBinding.t(),
          keyword(),
          SourceCapabilities.t() | nil
        ) :: {:ok, keyword()} | {:error, term()}
  def build(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        opts,
        capabilities
      )
      when is_list(opts) do
    source_opts = Keyword.get(opts, :source_opts, %{})

    adapter_opts =
      case Map.get(source_opts, request.logical_source, []) do
        opts when is_list(opts) -> opts
        _other -> []
      end

    adapter_opts
    |> maybe_put(:freshness_policy, Keyword.get(opts, :freshness_policy))
    |> maybe_put(:freshness_now, Keyword.get(opts, :freshness_now))
    |> maybe_put(:persisted?, Keyword.get(opts, :persisted?))
    |> put_source_capabilities(capabilities)
    |> Keyword.put(:source_binding, resolved_binding)
    |> put_source_connection_opts(resolved_binding, opts)
  end

  @spec merge_connection_options(
          keyword(),
          DataSource.t(),
          ResolvedSourceCredential.t() | SourceCredentialMaterial.t()
        ) :: keyword()
  def merge_connection_options(
        adapter_opts,
        %DataSource{} = data_source,
        %ResolvedSourceCredential{} = credential
      ) do
    profile = ResolvedSourceCredential.connection_profile(credential, data_source)

    adapter_opts
    |> Keyword.put(:source_connection_profile, profile)
    |> put_public_connection_opts(profile)
  end

  def merge_connection_options(
        adapter_opts,
        %DataSource{} = data_source,
        %SourceCredentialMaterial{} = credential_material
      ) do
    profile =
      SourceCredentialMaterial.redacted_connection_profile(credential_material, data_source)

    material = SourceCredentialMaterial.adapter_options(credential_material)

    adapter_opts
    |> Keyword.put(:source_connection_profile, profile)
    |> Keyword.put(:source_connection_material, material)
    |> put_public_connection_opts(profile)
    |> put_secret_connection_opts(material)
  end

  defp put_source_capabilities(adapter_opts, %SourceCapabilities{} = capabilities) do
    adapter_opts
    |> maybe_put(:source_capabilities, capabilities)
    |> maybe_put(:supported_time_axes, capabilities.supported_time_axes)
  end

  defp put_source_capabilities(adapter_opts, _capabilities), do: adapter_opts

  defp put_source_connection_opts(
         adapter_opts,
         %ResolvedSourceBinding{data_source: %DataSource{} = data_source},
         opts
       ) do
    case data_source.credentials_ref do
      credentials_ref when is_binary(credentials_ref) and credentials_ref != "" ->
        with {:ok, credential} <- resolve_source_credential(data_source, opts) do
          {:ok, merge_connection_options(adapter_opts, data_source, credential)}
        end

      _other ->
        {:ok, adapter_opts}
    end
  end

  defp resolve_source_credential(%DataSource{} = data_source, opts) do
    resolver_opts = credential_resolver_opts(data_source, opts)

    if credential_material_resolver_configured?(opts) do
      DataSourceReads.resolve_credential_material(data_source.credentials_ref, resolver_opts)
    else
      DataSourceReads.resolve_credential(data_source.credentials_ref, resolver_opts)
    end
  end

  defp credential_resolver_opts(%DataSource{} = data_source, opts) do
    opts
    |> Keyword.take([
      :credential_material_resolver,
      :credential_material_authorizer,
      :credential_secret_backend,
      :credential_configuration,
      :secret_backend,
      :env_material_profiles,
      :env_reader
    ])
    |> Keyword.merge(
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      data_source_id: data_source.data_source_id
    )
  end

  defp credential_material_resolver_configured?(opts) do
    Cadence.Secrets.ResolverConfiguration.data_source_configured?(opts)
  end

  defp put_public_connection_opts(opts, %{http_endpoint: http_endpoint})
       when is_binary(http_endpoint) do
    Keyword.put_new(opts, :http_endpoint, http_endpoint)
  end

  defp put_public_connection_opts(opts, _profile), do: opts

  defp put_secret_connection_opts(opts, material) when is_list(material) do
    opts
    |> maybe_put(:http_endpoint, Keyword.get(material, :http_endpoint))
    |> maybe_put(:headers, connection_headers(material))
  end

  defp connection_headers(material) when is_list(material) do
    headers = material |> Keyword.get(:headers, []) |> normalize_headers()

    cond do
      bearer_token = Keyword.get(material, :bearer_token) ->
        [{"authorization", "Bearer #{bearer_token}"} | headers]

      username = Keyword.get(material, :username) ->
        case Keyword.get(material, :password) do
          password when is_binary(password) ->
            [{"authorization", "Basic #{Base.encode64("#{username}:#{password}")}"} | headers]

          _other ->
            headers
        end

      true ->
        headers
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(_headers), do: []

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put_new(opts, key, value)
end
