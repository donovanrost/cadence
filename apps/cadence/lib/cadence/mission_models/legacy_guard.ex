defmodule Cadence.MissionModels.LegacyGuard do
  @moduledoc """
  Prevents transitional Derived Telemetry and Limits mutation or batch-runtime
  paths from competing with an active Mission Model generation.
  """

  alias Cadence.Activations
  alias Cadence.Control.MissionModelPromotion
  alias Cadence.Repo

  @spec ensure_available(binary()) :: :ok | {:error, term()}
  def ensure_available(mission_id) when is_binary(mission_id) do
    if Process.whereis(Repo), do: check_activation(mission_id), else: :ok
  end

  defp check_activation(mission_id) do
    case Activations.fetch_active_activation(mission_id) do
      {:error, :no_active_binding_set} ->
        :ok

      {:ok, activation} ->
        case MissionModelPromotion.runtime_basis(activation) do
          {:ok, %{mission_model_revision_id: revision_id, runtime_plans: plans}}
          when is_binary(revision_id) and map_size(plans) > 0 ->
            {:error, {:legacy_semantic_path_replaced_by_mission_model, revision_id}}

          {:ok, _legacy_binding_only} ->
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
