defmodule Cadence.Applications.StatusPlacement do
  @moduledoc """
  Host-approved placement for projecting an application's standard status.

  A placement opts an application into a cross-application host surface. It
  does not provide a renderer, route, query callback, or application-specific
  copy; those remain owned by the host and the registered status provider.
  """

  alias Cadence.Applications.ActionDefinition

  @type placement :: :comms_validation
  @type scope :: ActionDefinition.scope()

  @type t :: %__MODULE__{
          placement: placement(),
          scope: scope(),
          required?: boolean()
        }

  @enforce_keys [:placement, :scope]
  defstruct [:placement, :scope, required?: false]

  @placements [:comms_validation]
  @scopes [:organization, :mission, :spacecraft, :source_endpoint, :transport]

  @spec validate(t()) :: :ok | {:error, :invalid_application_status_placement}
  def validate(%__MODULE__{} = status_placement) do
    with true <- status_placement.placement in @placements,
         true <- status_placement.scope in @scopes,
         true <- is_boolean(status_placement.required?) do
      :ok
    else
      _invalid -> {:error, :invalid_application_status_placement}
    end
  end

  def validate(_status_placement), do: {:error, :invalid_application_status_placement}
end
