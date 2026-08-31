defmodule Cadence.Applications.SurfaceQueryContribution do
  @moduledoc "Bounded contribution describing one application-owned surface query provider."

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer(),
          query_id: binary(),
          query_version: pos_integer(),
          provider: module()
        }

  @enforce_keys [:application_key, :application_version, :query_id, :query_version, :provider]
  defstruct @enforce_keys
end
