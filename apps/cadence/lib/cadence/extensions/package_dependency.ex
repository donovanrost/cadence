defmodule Cadence.Extensions.PackageDependency do
  @moduledoc "Typed requirement on another compiled extension package."

  @type t :: %__MODULE__{
          package_id: binary(),
          minimum_version: pos_integer(),
          required: boolean()
        }

  @enforce_keys [:package_id]
  defstruct [:package_id, minimum_version: 1, required: true]

  @spec validate(t()) :: :ok | {:error, :invalid_extension_package_dependency}
  def validate(%__MODULE__{} = dependency) do
    if is_binary(dependency.package_id) and dependency.package_id != "" and
         is_integer(dependency.minimum_version) and dependency.minimum_version > 0 and
         is_boolean(dependency.required) do
      :ok
    else
      {:error, :invalid_extension_package_dependency}
    end
  end

  def validate(_dependency), do: {:error, :invalid_extension_package_dependency}
end
