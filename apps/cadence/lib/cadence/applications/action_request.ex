defmodule Cadence.Applications.ActionRequest do
  @moduledoc "Typed request for a host-standard or application-defined operation."

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer(),
          action_id: binary(),
          surface_id: binary() | nil,
          surface_version: pos_integer() | nil,
          params: map(),
          idempotency_key: binary() | nil
        }

  @enforce_keys [:application_key, :application_version, :action_id]
  defstruct [
    :application_key,
    :application_version,
    :action_id,
    :surface_id,
    :surface_version,
    :idempotency_key,
    params: %{}
  ]
end
