defmodule Cadence.GroundNetworks.ProviderAuditReferences do
  @moduledoc "Exact domain references attached to a provider audit entry."

  @fields [
    :provider_account_id,
    :provider_account_grant_id,
    :provider_id,
    :provider_reservation_id,
    :provider_change_id,
    :contact_id,
    :scheduled_contact_id
  ]

  @type t :: %__MODULE__{
          provider_account_id: binary() | nil,
          provider_account_grant_id: binary() | nil,
          provider_id: binary() | nil,
          provider_reservation_id: binary() | nil,
          provider_change_id: binary() | nil,
          contact_id: binary() | nil,
          scheduled_contact_id: binary() | nil
        }

  defstruct @fields

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    Enum.reduce(@fields, %__MODULE__{}, fn field, references ->
      Map.put(references, field, optional_text(attrs, field))
    end)
  end

  @spec fields() :: [atom()]
  def fields, do: @fields

  defp optional_text(attrs, key) do
    case value(attrs, key) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be non-empty text"
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
