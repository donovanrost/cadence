defmodule Cadence.Applications.LifecycleActionDefinition do
  @moduledoc "Typed host definition for one standard application lifecycle action."

  alias Cadence.Applications.{ActionConfirmation, ActionDefinition}

  @type button_variant :: :primary | :secondary | :danger

  @type t :: %__MODULE__{
          action_id: binary(),
          label: binary(),
          required_permission: binary(),
          effect: ActionDefinition.effect(),
          execution: ActionDefinition.execution(),
          button_variant: button_variant(),
          confirmation: ActionConfirmation.t() | nil
        }

  @enforce_keys [
    :action_id,
    :label,
    :required_permission,
    :effect,
    :execution,
    :button_variant
  ]

  defstruct [
    :action_id,
    :label,
    :required_permission,
    :effect,
    :execution,
    :button_variant,
    :confirmation
  ]

  @spec validate(t()) :: :ok | {:error, :invalid_application_lifecycle_action}
  def validate(%__MODULE__{} = action) do
    with true <- valid_text?(action.action_id),
         true <- valid_text?(action.label),
         true <- valid_text?(action.required_permission),
         true <- action.effect in [:none, :durable, :external],
         true <- action.execution in [:immediate, :asynchronous, :approval_required],
         true <- action.button_variant in [:primary, :secondary, :danger],
         :ok <- validate_confirmation(action.confirmation) do
      :ok
    else
      _invalid -> {:error, :invalid_application_lifecycle_action}
    end
  end

  def validate(_action), do: {:error, :invalid_application_lifecycle_action}

  defp validate_confirmation(nil), do: :ok

  defp validate_confirmation(%ActionConfirmation{} = confirmation),
    do: ActionConfirmation.validate(confirmation)

  defp validate_confirmation(_confirmation),
    do: {:error, :invalid_application_action_confirmation}

  defp valid_text?(value), do: is_binary(value) and value != ""
end
