defmodule Cadence.Applications.OpsDockSurface do
  @moduledoc "Resolved host-owned Ops Dock tab contributed by an installed application."

  alias Cadence.Applications.{ApplicationInstallation, SurfaceDefinition}

  @type t :: %__MODULE__{
          id: binary(),
          application_key: binary(),
          application_name: binary(),
          application_installation: ApplicationInstallation.t(),
          surface_definition: SurfaceDefinition.t(),
          label: binary(),
          order: integer()
        }

  @enforce_keys [
    :id,
    :application_key,
    :application_name,
    :application_installation,
    :surface_definition,
    :label,
    :order
  ]

  defstruct [
    :id,
    :application_key,
    :application_name,
    :application_installation,
    :surface_definition,
    :label,
    :order
  ]
end
