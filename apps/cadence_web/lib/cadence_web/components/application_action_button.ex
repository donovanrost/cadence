defmodule CadenceWeb.Components.ApplicationActionButton do
  @moduledoc "Shared host treatment for typed application action buttons."

  use Phoenix.Component

  import CadenceWeb.Components.Button, only: [button: 1]

  alias Cadence.Applications.ActionConfirmation

  attr :id, :string, required: true
  attr :action_id, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, values: ["button", "submit"], default: "button"
  attr :event, :string, default: nil
  attr :variant, :atom, values: [:primary, :ghost, :secondary, :danger], default: :primary
  attr :size, :atom, values: [:xs, :sm, :md], default: :sm
  attr :confirmation, ActionConfirmation, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def application_action_button(assigns) do
    ~H"""
    <.button
      id={@id}
      type={@type}
      variant={@variant}
      size={@size}
      class={@class}
      phx-click={@event}
      phx-value-action-id={@action_id}
      disabled={@disabled}
      data-confirmation-required={to_string(not is_nil(@confirmation))}
      data-confirmation-tone={confirmation_tone(@confirmation)}
      data-confirmation-title={confirmation_title(@confirmation)}
      data-confirmation-label={confirmation_label(@confirmation)}
      data-confirm={confirmation_prompt(@confirmation)}
      {@rest}
    >
      {@label}
    </.button>
    """
  end

  defp confirmation_prompt(nil), do: nil

  defp confirmation_prompt(%ActionConfirmation{} = confirmation),
    do: ActionConfirmation.prompt(confirmation)

  defp confirmation_tone(nil), do: nil
  defp confirmation_tone(%ActionConfirmation{tone: tone}), do: Atom.to_string(tone)

  defp confirmation_title(nil), do: nil
  defp confirmation_title(%ActionConfirmation{title: title}), do: title

  defp confirmation_label(nil), do: nil
  defp confirmation_label(%ActionConfirmation{confirm_label: label}), do: label
end
