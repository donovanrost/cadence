defmodule Cadence.Comms.ProviderTransportBasis do
  @moduledoc """
  Exact management-plane provider facts required to derive a managed Transport.

  The basis is supplied by orchestration code so the Comms store does not reach
  into mutable provider control state while persisting transport configuration.
  """

  @type t :: %__MODULE__{
          organization_id: binary(),
          mission_id: binary(),
          provider_id: binary(),
          provider_version: pos_integer(),
          display_name: binary(),
          provider_type: atom(),
          environment_ref: binary(),
          lifecycle_state: atom(),
          last_validated_at: DateTime.t() | nil,
          last_synced_at: DateTime.t() | nil,
          control_status: binary() | nil,
          inventory_sync_document: map()
        }

  @enforce_keys [
    :organization_id,
    :mission_id,
    :provider_id,
    :provider_version,
    :display_name,
    :provider_type,
    :environment_ref,
    :lifecycle_state,
    :last_validated_at,
    :last_synced_at,
    :control_status,
    :inventory_sync_document
  ]
  defstruct @enforce_keys
end
