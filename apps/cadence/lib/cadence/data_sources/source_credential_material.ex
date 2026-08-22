defmodule Cadence.DataSources.SourceCredentialMaterial do
  @moduledoc """
  Ephemeral credential material resolved for a data source.

  This struct is intentionally an in-process handoff value. It must not be
  persisted in source-health payloads, credential events, dashboard documents, or
  operator-visible assigns.
  """

  alias Cadence.DataSources.{DataSource, ResolvedSourceCredential}

  @type t :: %__MODULE__{
          credential: ResolvedSourceCredential.t(),
          material: map()
        }

  defstruct [
    :credential,
    material: %{}
  ]

  @allowed_material_keys [
    :http_endpoint,
    :username,
    :password,
    :bearer_token,
    :headers
  ]

  @secret_material_keys [:username, :password, :bearer_token, :headers]

  @spec new(ResolvedSourceCredential.t(), map()) :: t()
  def new(%ResolvedSourceCredential{} = credential, material) when is_map(material) do
    %__MODULE__{
      credential: credential,
      material: normalize_material(material)
    }
  end

  @spec adapter_options(t()) :: keyword()
  def adapter_options(%__MODULE__{material: material}) do
    material
    |> Enum.map(fn {key, value} -> {key, value} end)
    |> Enum.reject(fn {_key, value} -> empty?(value) end)
  end

  @spec redacted_connection_profile(t(), DataSource.t()) :: map()
  def redacted_connection_profile(%__MODULE__{} = resolved, %DataSource{} = data_source) do
    base_profile =
      resolved.credential
      |> ResolvedSourceCredential.connection_profile(data_source)
      |> Map.put(:secret_material?, true)

    base_profile
    |> Map.merge(public_connection_overrides(resolved))
    |> Map.put(:secret_material?, true)
    |> maybe_put_secret_fields(resolved)
  end

  defp normalize_material(material) do
    @allowed_material_keys
    |> Enum.reduce(%{}, fn key, acc ->
      value = metadata_value(material, key)

      if empty?(value) do
        acc
      else
        Map.put(acc, key, normalize_value(key, value))
      end
    end)
  end

  defp public_connection_overrides(%__MODULE__{material: material}) do
    material
    |> Map.take([:http_endpoint])
    |> Enum.reject(fn {_key, value} -> empty?(value) end)
    |> Map.new()
  end

  defp maybe_put_secret_fields(profile, %__MODULE__{material: material}) do
    fields =
      @secret_material_keys
      |> Enum.filter(fn key -> not empty?(Map.get(material, key)) end)
      |> Enum.map(&Atom.to_string/1)

    case fields do
      [] -> profile
      fields -> Map.put(profile, :secret_material_fields, fields)
    end
  end

  defp normalize_value(:headers, headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_value(:headers, headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_value(_key, value) when is_binary(value), do: value
  defp normalize_value(_key, value), do: to_string(value)

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp empty?(nil), do: true
  defp empty?(""), do: true
  defp empty?([]), do: true
  defp empty?(_value), do: false
end
