defmodule CadenceWeb.Components.ApplicationDomainAction do
  @moduledoc "Host-owned trigger for application-defined domain actions."

  use Phoenix.Component

  import CadenceWeb.Components.ApplicationActionButton,
    only: [application_action_button: 1]

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    SurfaceDefinition
  }

  attr :application_definition, ApplicationDefinition, required: true
  attr :surface_definition, SurfaceDefinition, required: true
  attr :action_id, :string, required: true
  attr :label, :string, required: true
  attr :id, :string, required: true
  attr :type, :string, values: ["button", "submit"], default: "button"
  attr :event, :string, default: nil
  attr :variant, :atom, values: [:primary, :ghost, :secondary, :danger], default: :primary
  attr :disabled, :boolean, default: false
  attr :size, :atom, values: [:xs, :sm, :md], default: :sm
  attr :class, :string, default: nil
  attr :rest, :global

  def application_domain_action(assigns) do
    action =
      resolve_action!(
        assigns.application_definition,
        assigns.surface_definition,
        assigns.action_id
      )

    assigns = assign(assigns, :action, action)

    ~H"""
    <.application_action_button
      id={@id}
      action_id={@action.action_id}
      label={@label}
      type={@type}
      event={@event}
      variant={@variant}
      size={@size}
      confirmation={@action.confirmation}
      disabled={@disabled}
      class={@class}
      data-application-domain-action={@action.action_id}
      data-action-version={@action.version}
      data-action-intent={Atom.to_string(@action.intent)}
      data-action-scope={Atom.to_string(@action.scope)}
      data-action-effect={Atom.to_string(@action.effect)}
      data-action-execution={Atom.to_string(@action.execution)}
      {@rest}
    />
    """
  end

  defp resolve_action!(
         %ApplicationDefinition{} = application,
         %SurfaceDefinition{} = surface,
         action_id
       ) do
    with true <- action_id in surface.actions,
         {:ok, %ActionDefinition{} = action} <-
           ApplicationDefinition.fetch_action(application, action_id),
         true <- action.scope == surface.scope,
         :ok <- ActionDefinition.validate(action) do
      action
    else
      reason -> raise ArgumentError, "invalid domain action: #{inspect(reason)}"
    end
  end
end
