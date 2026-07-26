defmodule CadenceWeb.Components.ApplicationLifecycleAction do
  @moduledoc "Host-owned button and confirmation treatment for standard lifecycle actions."

  use Phoenix.Component

  import CadenceWeb.Components.ApplicationActionButton,
    only: [application_action_button: 1]

  alias Cadence.Applications.{
    LifecycleActionDefinition,
    LifecycleActions,
    LifecycleContract
  }

  attr :action_id, :string, required: true
  attr :contract, LifecycleContract, default: nil
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :disabled, :boolean, default: false
  attr :size, :atom, values: [:xs, :sm, :md], default: :sm
  attr :class, :string, default: nil
  attr :rest, :global

  def application_lifecycle_action(assigns) do
    action = resolve_action!(assigns.contract, assigns.action_id)
    assigns = assign(assigns, :action, action)

    ~H"""
    <.application_action_button
      id={@id}
      action_id={@action.action_id}
      label={@action.label}
      variant={@action.button_variant}
      size={@size}
      class={@class}
      event={@event}
      confirmation={@action.confirmation}
      disabled={@disabled}
      data-application-lifecycle-action={@action.action_id}
      data-lifecycle-effect={Atom.to_string(@action.effect)}
      data-lifecycle-execution={Atom.to_string(@action.execution)}
      {@rest}
    />
    """
  end

  defp resolve_action!(nil, action_id) do
    case LifecycleActions.fetch(action_id) do
      {:ok, action} -> action
      {:error, reason} -> raise ArgumentError, "invalid lifecycle action: #{inspect(reason)}"
    end
  end

  defp resolve_action!(%LifecycleContract{} = contract, action_id) do
    case LifecycleContract.fetch_action(contract, action_id) do
      {:ok, %LifecycleActionDefinition{} = action} -> action
      {:error, reason} -> raise ArgumentError, "invalid lifecycle action: #{inspect(reason)}"
    end
  end
end
