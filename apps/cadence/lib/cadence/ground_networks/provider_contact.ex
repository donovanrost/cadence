defmodule Cadence.GroundNetworks.ProviderContact do
  @moduledoc "Validated external Contact with independent contact, pass, and delivery state."

  alias Cadence.GroundNetworks.{DeliveryDescriptor, Validation}

  @statuses %{
    "pending" => :pending,
    "confirmed" => :confirmed,
    "active" => :active,
    "completed" => :completed,
    "rejected" => :rejected,
    "canceling" => :canceling,
    "canceled" => :canceled,
    "failed" => :failed
  }
  @pass_phases %{
    "scheduled" => :scheduled,
    "prepass" => :prepass,
    "pass" => :pass,
    "postpass" => :postpass,
    "closed" => :closed
  }

  @type t :: %__MODULE__{
          id: binary(),
          client_reference: binary(),
          opportunity_ref: binary(),
          spacecraft_ref: binary(),
          ground_station_ref: binary(),
          service_profile_ref: binary(),
          delivery_profile_ref: binary(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          status: atom(),
          provider_status: binary(),
          pass_phase: atom(),
          delivery: DeliveryDescriptor.t(),
          status_reason: binary() | nil,
          tags: map(),
          extensions: map(),
          evidence: map()
        }

  defstruct [
    :id,
    :client_reference,
    :opportunity_ref,
    :spacecraft_ref,
    :ground_station_ref,
    :service_profile_ref,
    :delivery_profile_ref,
    :starts_at,
    :ends_at,
    :status,
    :provider_status,
    :pass_phase,
    :delivery,
    :status_reason,
    tags: %{},
    extensions: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(contact) when is_map(contact) do
    contact = Validation.sanitize(contact)

    with {:ok, id} <- Validation.required_string(contact, "id"),
         {:ok, client_reference} <- Validation.required_string(contact, "client_reference"),
         {:ok, opportunity_ref} <- Validation.required_string(contact, "opportunity_ref"),
         {:ok, spacecraft_ref} <- Validation.required_string(contact, "spacecraft_ref"),
         {:ok, ground_station_ref} <- Validation.required_string(contact, "ground_station_ref"),
         {:ok, service_profile_ref} <-
           Validation.required_string(contact, "service_profile_ref"),
         {:ok, delivery_profile_ref} <-
           Validation.required_string(contact, "delivery_profile_ref"),
         {:ok, starts_at} <- Validation.datetime(contact, "starts_at"),
         {:ok, ends_at} <- Validation.datetime(contact, "ends_at"),
         true <- DateTime.before?(starts_at, ends_at),
         {:ok, status} <- Validation.member(contact, "status", @statuses),
         {:ok, pass_phase} <- Validation.member(contact, "pass_phase", @pass_phases),
         {:ok, delivery} <- DeliveryDescriptor.from_external(contact["delivery"]),
         {:ok, status_reason} <- Validation.optional_string(contact, "status_reason"),
         {:ok, tags} <- Validation.object(contact, "tags"),
         {:ok, extensions} <- Validation.object(contact, "extensions") do
      {:ok,
       %__MODULE__{
         id: id,
         client_reference: client_reference,
         opportunity_ref: opportunity_ref,
         spacecraft_ref: spacecraft_ref,
         ground_station_ref: ground_station_ref,
         service_profile_ref: service_profile_ref,
         delivery_profile_ref: delivery_profile_ref,
         starts_at: starts_at,
         ends_at: ends_at,
         status: status,
         provider_status: contact["status"],
         pass_phase: pass_phase,
         delivery: delivery,
         status_reason: status_reason,
         tags: tags,
         extensions: extensions,
         evidence: contact
       }}
    else
      false -> Validation.malformed("ends_at")
      error -> error
    end
  end

  def from_external(_contact), do: Validation.malformed(:contact)

  @spec to_reservation_result(t()) :: map()
  def to_reservation_result(%__MODULE__{} = contact) do
    %{
      "id" => contact.id,
      "provider_contact_ref" => contact.id,
      "client_reference" => contact.client_reference,
      "status" => Atom.to_string(contact.status),
      "provider_status" => contact.provider_status,
      "pass_phase" => Atom.to_string(contact.pass_phase),
      "delivery_state" => Atom.to_string(contact.delivery.status),
      "delivery_descriptor" => DeliveryDescriptor.to_map(contact.delivery),
      "starts_at" => DateTime.to_iso8601(contact.starts_at),
      "ends_at" => DateTime.to_iso8601(contact.ends_at),
      "provider_evidence" => contact.evidence
    }
  end
end
