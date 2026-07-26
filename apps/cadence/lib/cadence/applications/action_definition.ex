defmodule Cadence.Applications.ActionDefinition do
  @moduledoc """
  Typed metadata for an application-defined domain action.

  Host-standard installation, configuration, and activation operations are
  declared through an application's lifecycle contract instead of being
  redefined here.
  """

  alias Cadence.Applications.ActionConfirmation

  @type intent :: :configuration | :diagnostic | :operation | :maintenance
  @type scope :: :organization | :mission | :spacecraft | :source_endpoint | :transport
  @type effect :: :none | :durable | :external
  @type execution :: :immediate | :asynchronous | :approval_required

  @type t :: %__MODULE__{
          action_id: binary(),
          version: pos_integer(),
          intent: intent(),
          scope: scope(),
          input_contract: map(),
          result_contract: map(),
          required_permission: binary(),
          effect: effect(),
          execution: execution(),
          concurrency: map(),
          confirmation: ActionConfirmation.t() | nil,
          progress_contract: map() | nil
        }

  @enforce_keys [
    :action_id,
    :version,
    :intent,
    :scope,
    :required_permission,
    :effect,
    :execution
  ]

  defstruct [
    :action_id,
    :version,
    :intent,
    :scope,
    :required_permission,
    :effect,
    :execution,
    :progress_contract,
    input_contract: %{},
    result_contract: %{},
    concurrency: %{},
    confirmation: nil
  ]

  @intents [:configuration, :diagnostic, :operation, :maintenance]
  @scopes [:organization, :mission, :spacecraft, :source_endpoint, :transport]
  @effects [:none, :durable, :external]
  @executions [:immediate, :asynchronous, :approval_required]

  @spec validate(t()) :: :ok | {:error, :invalid_application_action_definition}
  def validate(%__MODULE__{} = action) do
    with true <- valid_text?(action.action_id),
         true <- is_integer(action.version) and action.version > 0,
         true <- action.intent in @intents,
         true <- action.scope in @scopes,
         true <- is_map(action.input_contract),
         true <- is_map(action.result_contract),
         true <- valid_text?(action.required_permission),
         true <- action.effect in @effects,
         true <- action.execution in @executions,
         true <- is_map(action.concurrency),
         :ok <- validate_confirmation(action.confirmation),
         true <- is_nil(action.progress_contract) or is_map(action.progress_contract) do
      :ok
    else
      _invalid -> {:error, :invalid_application_action_definition}
    end
  end

  def validate(_action), do: {:error, :invalid_application_action_definition}

  defp validate_confirmation(nil), do: :ok

  defp validate_confirmation(%ActionConfirmation{} = confirmation),
    do: ActionConfirmation.validate(confirmation)

  defp validate_confirmation(_confirmation),
    do: {:error, :invalid_application_action_confirmation}

  defp valid_text?(value), do: is_binary(value) and value != ""
end
