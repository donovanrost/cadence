defmodule Cadence.Applications.ReleaseContribution do
  @moduledoc "Plain versioned frontend release metadata contributed by an application owner."

  @type federation :: :module_federation | :native_federation

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer(),
          surface_id: binary(),
          surface_version: pos_integer(),
          federation: federation(),
          release_id: binary(),
          remote_name: binary(),
          manifest_path: binary(),
          exposed_module: binary()
        }

  @enforce_keys [
    :application_key,
    :application_version,
    :surface_id,
    :surface_version,
    :federation,
    :release_id,
    :remote_name,
    :manifest_path,
    :exposed_module
  ]

  defstruct @enforce_keys

  @spec validate(t()) :: :ok | {:error, :invalid_release_contribution}
  def validate(%__MODULE__{} = contribution) do
    with true <- valid_text?(contribution.application_key),
         true <- positive_integer?(contribution.application_version),
         true <- valid_text?(contribution.surface_id),
         true <- positive_integer?(contribution.surface_version),
         true <- contribution.federation in [:module_federation, :native_federation],
         true <- valid_text?(contribution.release_id),
         true <- valid_text?(contribution.remote_name),
         true <- valid_asset_path?(contribution.manifest_path),
         true <- valid_module?(contribution.exposed_module) do
      :ok
    else
      _invalid -> {:error, :invalid_release_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_release_contribution}

  @spec key(t()) :: {binary(), pos_integer(), binary(), pos_integer()}
  def key(%__MODULE__{} = contribution),
    do: {
      contribution.application_key,
      contribution.application_version,
      contribution.surface_id,
      contribution.surface_version
    }

  @spec release(t()) :: map()
  def release(%__MODULE__{} = contribution) do
    Map.take(Map.from_struct(contribution), [
      :federation,
      :release_id,
      :remote_name,
      :manifest_path,
      :exposed_module
    ])
  end

  defp valid_asset_path?(value), do: valid_text?(value) and String.starts_with?(value, "/assets/")
  defp valid_module?(value), do: valid_text?(value) and String.starts_with?(value, "./")
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_text?(value), do: is_binary(value) and value != "" and String.valid?(value)
end
