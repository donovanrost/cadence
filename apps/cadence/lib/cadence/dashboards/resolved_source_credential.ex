defmodule Cadence.Dashboards.ResolvedSourceCredential do
  @moduledoc """
  Non-secret credential descriptor returned by the dashboard source credential resolver.
  """

  alias Cadence.Dashboards.{DataSource, SourceCredentialReference}

  @type t :: %__MODULE__{
          credentials_ref: binary(),
          organization_id: binary(),
          mission_id: binary() | nil,
          data_source_id: binary() | nil,
          owner: SourceCredentialReference.owner(),
          kind: SourceCredentialReference.kind(),
          provider: binary() | nil,
          status: SourceCredentialReference.status(),
          credential_version: pos_integer(),
          current_event_id: binary() | nil,
          metadata: map(),
          secret_material?: false
        }

  defstruct [
    :credentials_ref,
    :organization_id,
    :mission_id,
    :data_source_id,
    :owner,
    :kind,
    :provider,
    :status,
    :credential_version,
    :current_event_id,
    metadata: %{},
    secret_material?: false
  ]

  @spec from_reference(SourceCredentialReference.t()) :: t()
  def from_reference(%SourceCredentialReference{} = reference) do
    %__MODULE__{
      credentials_ref: reference.credentials_ref,
      organization_id: reference.organization_id,
      mission_id: reference.mission_id,
      data_source_id: reference.data_source_id,
      owner: reference.owner,
      kind: reference.kind,
      provider: reference.provider,
      status: reference.status,
      credential_version: reference.credential_version,
      current_event_id: reference.current_event_id,
      metadata: reference.metadata,
      secret_material?: false
    }
  end

  @spec connection_profile(t(), DataSource.t()) :: map()
  def connection_profile(%__MODULE__{} = credential, %DataSource{} = data_source) do
    endpoint_ref =
      metadata_value(data_source.metadata, :endpoint_ref) ||
        metadata_value(credential.metadata, :endpoint_ref)

    http_endpoint =
      safe_http_endpoint(
        metadata_value(data_source.metadata, :http_endpoint) ||
          metadata_value(credential.metadata, :http_endpoint)
      )

    %{
      credentials_ref: credential.credentials_ref,
      credential_provider: credential.provider,
      credential_kind: credential.kind,
      credential_owner: credential.owner,
      credential_version: credential.credential_version,
      credential_status: credential.status,
      credential_event_id: credential.current_event_id,
      data_source_id: data_source.data_source_id,
      data_source_kind: data_source.kind,
      data_source_owner: data_source.owner,
      isolation_level: data_source.isolation_level,
      physical_isolation: DataSource.isolation_profile(data_source),
      endpoint_ref: endpoint_ref,
      http_endpoint: http_endpoint,
      secret_material?: false
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp safe_http_endpoint(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, userinfo: nil}
      when scheme in ["http", "https"] and is_binary(host) ->
        value

      _other ->
        nil
    end
  end

  defp safe_http_endpoint(_value), do: nil
end
