defmodule Cadence.Applications.ApplicationDependency do
  @moduledoc """
  Typed requirement on another installed product application.

  Dependencies name compiled application identifiers and host relationships.
  They do not perform installation, activation, or arbitrary lookup callbacks.
  """

  @type scope_relation :: :same_host | :mission

  @type t :: %__MODULE__{
          application_key: binary(),
          minimum_version: pos_integer(),
          scope: scope_relation(),
          required: boolean(),
          description: binary() | nil
        }

  @enforce_keys [:application_key, :scope]
  defstruct [:application_key, :scope, :description, minimum_version: 1, required: true]

  @spec validate(t()) :: :ok | {:error, :invalid_application_dependency}
  def validate(%__MODULE__{} = dependency) do
    if valid_text?(dependency.application_key) and
         is_integer(dependency.minimum_version) and dependency.minimum_version > 0 and
         dependency.scope in [:same_host, :mission] and is_boolean(dependency.required) and
         optional_text?(dependency.description) do
      :ok
    else
      {:error, :invalid_application_dependency}
    end
  end

  def validate(_dependency), do: {:error, :invalid_application_dependency}

  defp valid_text?(value), do: is_binary(value) and value != ""
  defp optional_text?(nil), do: true
  defp optional_text?(value), do: is_binary(value)
end
