defmodule Cadence.Activations.GenerationReceipts do
  @moduledoc "Durable completion evidence for a mission generation admitted by the runtime."

  import Ecto.Query

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Activations.BindingSetActivationRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @doc """
  Records the first successful convergence of the active scoped generation.

  The active pointer is locked for the statement, so a delayed apply cannot record a receipt
  after another activation has taken its place.
  """
  @spec record(BindingSetActivation.t(), DateTime.t()) :: :ok | {:error, term()}
  def record(%BindingSetActivation{organization_id: nil}, _applied_at), do: :ok

  def record(%BindingSetActivation{} = activation, applied_at) do
    sql = """
    WITH active AS (
      SELECT organization_id, mission_id, generation, activation_id, binding_set_id, binding_set_version
      FROM mission_active_binding_sets
      WHERE organization_id = $1 AND mission_id = $2 AND activation_id = $3 AND generation = $4
        AND binding_set_id = $5 AND binding_set_version = $6
      FOR SHARE
    ), written AS (
      INSERT INTO mission_generation_receipts
        (organization_id, mission_id, generation, activation_id, binding_set_id, binding_set_version, applied_at)
      SELECT organization_id, mission_id, generation, activation_id, binding_set_id, binding_set_version,
             $7::timestamptz AT TIME ZONE 'UTC'
      FROM active
      ON CONFLICT (organization_id, mission_id, generation) DO NOTHING
      RETURNING 1
    )
    SELECT EXISTS(SELECT 1 FROM active), EXISTS(SELECT 1 FROM written)
    """

    params = [
      activation.organization_id,
      activation.mission_id,
      activation.activation_id,
      activation.generation,
      activation.binding_set_id,
      activation.binding_set_version,
      applied_at
    ]

    case Repo.query(sql, params, source: "mission_generation_receipts") do
      {:ok, %{rows: [[true, true]]}} ->
        ScopedReadUpdates.publish(
          :spacecraft_configuration_changed,
          activation.organization_id,
          activation.mission_id
        )

        :ok

      {:ok, %{rows: [[true, false]]}} ->
        :ok

      {:ok, %{rows: [[false, false]]}} ->
        {:error, :spacecraft_configuration_review_stale}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the latest applied activation and its first completion time in this mission."
  @spec latest(binary(), binary()) :: {BindingSetActivation.t(), DateTime.t()} | nil
  def latest(org, mission) do
    from(receipt in "mission_generation_receipts",
      join: activation in BindingSetActivationRow,
      on:
        receipt.activation_id == activation.activation_id and
          receipt.organization_id == activation.organization_id and
          receipt.mission_id == activation.mission_id,
      where: receipt.organization_id == ^org and receipt.mission_id == ^mission,
      order_by: [desc: receipt.generation],
      limit: 1,
      select: {activation, type(receipt.applied_at, :utc_datetime_usec)}
    )
    |> Repo.one()
    |> case do
      {row, applied_at} -> {BindingSetActivationRow.to_domain(row), applied_at}
      nil -> nil
    end
  end

  @doc false
  def fleet_at_query(org, mission, %DateTime{} = at) do
    effective =
      from(receipt in "mission_generation_receipts",
        where:
          receipt.organization_id == ^org and receipt.mission_id == ^mission and
            receipt.applied_at <= type(^at, :utc_datetime_usec),
        order_by: [desc: receipt.applied_at, desc: receipt.generation],
        limit: 1,
        select: %{
          organization_id: receipt.organization_id,
          mission_id: receipt.mission_id,
          activation_id: receipt.activation_id
        }
      )

    from(receipt in subquery(effective),
      join: activation in BindingSetActivationRow,
      on:
        activation.activation_id == receipt.activation_id and
          activation.organization_id == receipt.organization_id and
          activation.mission_id == receipt.mission_id,
      where:
        fragment("? #>> '{value,spacecraft_configuration_version}'", activation.metadata) == "2",
      where:
        fragment("? #>> '{value,fleet,mission_id}'", activation.metadata) == receipt.mission_id,
      select: %{
        organization_id: receipt.organization_id,
        mission_id: receipt.mission_id,
        fleet_sha256: fragment("? #>> '{value,fleet,sha256}'", activation.metadata)
      }
    )
  end
end
