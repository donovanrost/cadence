defmodule Cadence.Applications.LifecycleContract do
  @moduledoc "Standard lifecycle actions supported by a registered application."

  alias Cadence.Applications.{LifecycleActionDefinition, LifecycleActions}

  @type t :: %__MODULE__{actions: [binary()]}

  defstruct actions: []

  @spec validate(t()) :: :ok | {:error, :invalid_application_lifecycle_contract}
  def validate(%__MODULE__{actions: actions}) when is_list(actions) do
    if unique_actions?(actions) and Enum.all?(actions, &known_action?/1) do
      :ok
    else
      {:error, :invalid_application_lifecycle_contract}
    end
  end

  def validate(_contract), do: {:error, :invalid_application_lifecycle_contract}

  @spec fetch_action(t(), binary()) ::
          {:ok, LifecycleActionDefinition.t()} | {:error, :undeclared_application_action}
  def fetch_action(%__MODULE__{actions: actions}, action_id) when is_binary(action_id) do
    if action_id in actions do
      case LifecycleActions.fetch(action_id) do
        {:ok, action} -> {:ok, action}
        {:error, _reason} -> {:error, :undeclared_application_action}
      end
    else
      {:error, :undeclared_application_action}
    end
  end

  def fetch_action(%__MODULE__{}, _action_id), do: {:error, :undeclared_application_action}

  defp unique_actions?(actions), do: length(Enum.uniq(actions)) == length(actions)

  defp known_action?(action_id) do
    case LifecycleActions.fetch(action_id) do
      {:ok, %LifecycleActionDefinition{} = action} ->
        LifecycleActionDefinition.validate(action) == :ok

      {:error, _reason} ->
        false
    end
  end
end
