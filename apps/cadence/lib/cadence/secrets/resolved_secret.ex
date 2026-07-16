defmodule Cadence.Secrets.ResolvedSecret do
  @moduledoc "Ephemeral secret material plus non-secret registry and backend identity."

  @derive {Inspect,
           only: [
             :reference,
             :organization_id,
             :provider_account_id,
             :registry_version,
             :backend_version,
             :fingerprint,
             :expires_at
           ]}

  @type t :: %__MODULE__{
          reference: binary(),
          organization_id: binary() | nil,
          provider_account_id: binary() | nil,
          registry_version: pos_integer() | nil,
          backend_version: binary() | nil,
          fingerprint: binary() | nil,
          expires_at: DateTime.t() | nil,
          material: map()
        }

  defstruct [
    :reference,
    :organization_id,
    :provider_account_id,
    :registry_version,
    :backend_version,
    :fingerprint,
    :expires_at,
    material: %{}
  ]

  @spec new(struct() | map(), map(), map()) :: t()
  def new(descriptor, material, metadata \\ %{})
      when is_map(descriptor) and is_map(material) and is_map(metadata) do
    %__MODULE__{
      reference:
        descriptor_value(descriptor, [:provider_credential_ref, :credentials_ref, :reference]),
      organization_id: descriptor_value(descriptor, [:organization_id]),
      provider_account_id: descriptor_value(descriptor, [:provider_account_id]),
      registry_version: descriptor_value(descriptor, [:registry_version, :credential_version]),
      backend_version: metadata_value(metadata, :backend_version),
      fingerprint: metadata_value(metadata, :fingerprint),
      expires_at: normalize_expiry(metadata_value(metadata, :expires_at)),
      material: material
    }
  end

  defp descriptor_value(descriptor, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(descriptor, key, Map.get(descriptor, to_string(key)))
    end)
  end

  defp metadata_value(metadata, key),
    do: Map.get(metadata, key, Map.get(metadata, to_string(key)))

  defp normalize_expiry(nil), do: nil
  defp normalize_expiry(%DateTime{} = expiry), do: DateTime.truncate(expiry, :microsecond)

  defp normalize_expiry(expiry) when is_binary(expiry) do
    case DateTime.from_iso8601(expiry) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :microsecond)
      _error -> nil
    end
  end

  defp normalize_expiry(_expiry), do: nil
end
