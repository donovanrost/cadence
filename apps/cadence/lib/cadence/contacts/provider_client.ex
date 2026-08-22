defmodule Cadence.Contacts.ProviderClient do
  @moduledoc """
  Provider-neutral control-plane boundary for external ground networks.

  This remains separate from `Cadence.ProviderAdapters.Adapter`, which owns
  path-local byte I/O only after a Contact has been realized.
  """

  alias Cadence.GroundNetworks.{
    DeliveryProfile,
    Opportunity,
    ProviderCapabilities,
    ProviderContact,
    ProviderContext,
    ProviderError,
    ProviderEvent,
    ServiceProfile
  }

  @type provider_result(value) :: {:ok, value} | {:error, ProviderError.t() | term()}
  @type opportunity_page :: %{
          data: [Opportunity.t()],
          next_cursor: binary() | nil,
          truncated: boolean(),
          provider_evidence: map()
        }
  @type event_page :: %{
          data: [ProviderEvent.t()],
          next_cursor: binary() | non_neg_integer() | nil,
          truncated: boolean()
        }

  @callback validate_connection(ProviderContext.t(), keyword()) :: provider_result(map())
  @callback capabilities(ProviderContext.t(), keyword()) ::
              provider_result(ProviderCapabilities.t())
  @callback list_spacecraft(ProviderContext.t(), map(), keyword()) :: provider_result([map()])
  @callback list_ground_stations(ProviderContext.t(), map(), keyword()) ::
              provider_result([map()])
  @callback list_service_profiles(ProviderContext.t(), map(), keyword()) ::
              provider_result([ServiceProfile.t()])
  @callback list_delivery_profiles(ProviderContext.t(), map(), keyword()) ::
              provider_result([DeliveryProfile.t()])
  @callback provision_delivery_profile(ProviderContext.t(), map(), keyword()) ::
              provider_result(DeliveryProfile.t())
  @callback search_opportunities(ProviderContext.t(), map(), keyword()) ::
              provider_result(opportunity_page())
  @callback reserve_contact(ProviderContext.t(), map(), keyword()) ::
              provider_result(ProviderContact.t())
  @callback describe_contact(ProviderContext.t(), binary(), keyword()) ::
              provider_result(ProviderContact.t())
  @callback modify_contact(ProviderContext.t(), binary(), map(), keyword()) ::
              provider_result(ProviderContact.t())
  @callback cancel_contact(ProviderContext.t(), binary(), keyword()) ::
              provider_result(ProviderContact.t())
  @callback find_contact_by_client_reference(ProviderContext.t(), binary(), keyword()) ::
              provider_result(ProviderContact.t())
  @callback events(ProviderContext.t(), binary() | non_neg_integer() | nil, keyword()) ::
              provider_result(event_page())

  @optional_callbacks provision_delivery_profile: 3,
                      modify_contact: 4,
                      find_contact_by_client_reference: 3,
                      events: 3
end
