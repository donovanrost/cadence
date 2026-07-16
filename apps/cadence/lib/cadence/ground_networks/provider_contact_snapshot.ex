defmodule Cadence.GroundNetworks.ProviderContactSnapshot do
  @moduledoc "Normalized authoritative snapshot of one provider Contact revision."

  alias Cadence.GroundNetworks.{DeliveryDescriptor, ProviderContact}

  @type t :: %__MODULE__{
          provider_contact_ref: binary(),
          provider_revision: pos_integer(),
          client_reference: binary(),
          opportunity_ref: binary(),
          spacecraft_ref: binary(),
          ground_station_ref: binary(),
          antenna_or_service_pool_ref: binary() | nil,
          service_profile_ref: binary(),
          delivery_profile_ref: binary(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          status: atom(),
          pass_phase: atom(),
          delivery_state: atom(),
          delivery_descriptor_document: map(),
          status_reason: binary() | nil,
          extensions_document: map()
        }

  defstruct [
    :provider_contact_ref,
    :provider_revision,
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
    :status_reason,
    extensions_document: %{}
  ]

  @spec from_contact(ProviderContact.t()) :: t()
  def from_contact(%ProviderContact{} = contact) do
    %__MODULE__{
      provider_contact_ref: contact.id,
      provider_revision: contact.provider_revision,
      client_reference: contact.client_reference,
      opportunity_ref: contact.opportunity_ref,
      spacecraft_ref: contact.spacecraft_ref,
      ground_station_ref: contact.ground_station_ref,
      antenna_or_service_pool_ref: contact.antenna_or_service_pool_ref,
      service_profile_ref: contact.service_profile_ref,
      delivery_profile_ref: contact.delivery_profile_ref,
      starts_at: contact.starts_at,
      ends_at: contact.ends_at,
      status: contact.status,
      pass_phase: contact.pass_phase,
      delivery_state: contact.delivery.status,
      delivery_descriptor_document: DeliveryDescriptor.to_map(contact.delivery),
      status_reason: contact.status_reason,
      extensions_document: contact.extensions
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = snapshot) do
    %{
      "provider_contact_ref" => snapshot.provider_contact_ref,
      "provider_revision" => snapshot.provider_revision,
      "client_reference" => snapshot.client_reference,
      "opportunity_ref" => snapshot.opportunity_ref,
      "spacecraft_ref" => snapshot.spacecraft_ref,
      "ground_station_ref" => snapshot.ground_station_ref,
      "antenna_or_service_pool_ref" => snapshot.antenna_or_service_pool_ref,
      "service_profile_ref" => snapshot.service_profile_ref,
      "delivery_profile_ref" => snapshot.delivery_profile_ref,
      "starts_at" => DateTime.to_iso8601(snapshot.starts_at),
      "ends_at" => DateTime.to_iso8601(snapshot.ends_at),
      "status" => Atom.to_string(snapshot.status),
      "pass_phase" => Atom.to_string(snapshot.pass_phase),
      "delivery_state" => Atom.to_string(snapshot.delivery_state),
      "delivery_descriptor" => snapshot.delivery_descriptor_document,
      "status_reason" => snapshot.status_reason,
      "extensions" => snapshot.extensions_document
    }
  end
end
