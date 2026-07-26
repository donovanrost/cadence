defmodule Cadence.Applications.SurfaceQueryRequest do
  @moduledoc "Typed host request for one declared application surface data contract."

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer(),
          surface_id: binary(),
          surface_version: pos_integer(),
          query_id: binary(),
          query_version: pos_integer(),
          params: map()
        }

  @enforce_keys [
    :application_key,
    :application_version,
    :surface_id,
    :surface_version,
    :query_id,
    :query_version
  ]

  defstruct [
    :application_key,
    :application_version,
    :surface_id,
    :surface_version,
    :query_id,
    :query_version,
    params: %{}
  ]
end
