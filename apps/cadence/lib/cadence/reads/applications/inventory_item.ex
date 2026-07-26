defmodule Cadence.Reads.Applications.InventoryItem do
  @moduledoc "Host-standard application inventory item composed from package, lifecycle, and status data."

  alias Cadence.Applications.{ApplicationDefinition, ApplicationInstallation, Status}

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer() | nil,
          display_name: binary(),
          description: binary(),
          definition: ApplicationDefinition.t() | nil,
          installation: ApplicationInstallation.t() | nil,
          lifecycle_state: ApplicationInstallation.lifecycle_state() | nil,
          declared?: boolean(),
          installable?: boolean(),
          manageable?: boolean(),
          uninstallable?: boolean(),
          status: Status.t()
        }

  @enforce_keys [
    :application_key,
    :display_name,
    :description,
    :declared?,
    :installable?,
    :manageable?,
    :uninstallable?,
    :status
  ]

  defstruct [
    :application_key,
    :application_version,
    :display_name,
    :description,
    :definition,
    :installation,
    :lifecycle_state,
    :status,
    declared?: false,
    installable?: false,
    manageable?: false,
    uninstallable?: false
  ]
end
