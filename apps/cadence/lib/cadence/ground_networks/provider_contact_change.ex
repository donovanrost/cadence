defmodule Cadence.GroundNetworks.ProviderContactChange do
  @moduledoc "Deterministic difference between two authoritative Contact snapshots."

  alias Cadence.GroundNetworks.ProviderContactSnapshot

  @tracked_fields [
    :client_reference,
    :opportunity_ref,
    :spacecraft_ref,
    :ground_station_ref,
    :antenna_or_service_pool_ref,
    :service_profile_ref,
    :delivery_profile_ref,
    :starts_at,
    :ends_at,
    :status,
    :pass_phase,
    :delivery_state,
    :delivery_descriptor_document,
    :status_reason
  ]

  @type t :: %__MODULE__{
          provider_contact_ref: binary(),
          from_revision: pos_integer(),
          to_revision: pos_integer(),
          before: ProviderContactSnapshot.t(),
          after: ProviderContactSnapshot.t(),
          changed_fields: map()
        }

  defstruct [
    :provider_contact_ref,
    :from_revision,
    :to_revision,
    :before,
    :after,
    changed_fields: %{}
  ]

  @spec between(ProviderContactSnapshot.t(), ProviderContactSnapshot.t()) ::
          {:ok, t()} | {:error, term()}
  def between(
        %ProviderContactSnapshot{} = before,
        %ProviderContactSnapshot{} = current
      ) do
    cond do
      before.provider_contact_ref != current.provider_contact_ref ->
        {:error, :provider_contact_identity_mismatch}

      current.provider_revision <= before.provider_revision ->
        {:error, :provider_contact_revision_not_advanced}

      true ->
        changed_fields = changed_fields(before, current)

        if changed_fields == %{} do
          {:error, :provider_contact_has_no_change}
        else
          {:ok,
           %__MODULE__{
             provider_contact_ref: before.provider_contact_ref,
             from_revision: before.provider_revision,
             to_revision: current.provider_revision,
             before: before,
             after: current,
             changed_fields: changed_fields
           }}
        end
    end
  end

  defp changed_fields(before, current) do
    Enum.reduce(@tracked_fields, %{}, fn field, acc ->
      previous = Map.fetch!(before, field)
      current_value = Map.fetch!(current, field)

      if previous == current_value do
        acc
      else
        Map.put(acc, Atom.to_string(field), %{
          "before" => encode_value(previous),
          "after" => encode_value(current_value)
        })
      end
    end)
  end

  defp encode_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value), do: value
end
