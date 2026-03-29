defmodule Cadence.Activations do
  @moduledoc """
  Durable activation control plane for mission-scoped binding-set bases.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Activations.BindingSetActivation
  alias Cadence.Governance
  alias Cadence.Missions
  alias Cadence.Persistence.Schemas.{ActiveBindingSetRow, BindingSetActivationRow}
  alias Cadence.Repo

  @spec activate_binding_set(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def activate_binding_set(organization_id, mission_id, binding_set_id, version, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 and is_list(opts) do
    metadata = Keyword.get(opts, :metadata, %{})
    activated_at = Keyword.get(opts, :activated_at, DateTime.utc_now())

    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, _binding_set} <-
           Governance.fetch_binding_set(organization_id, mission_id, binding_set_id, version) do
      activation =
        BindingSetActivation.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          binding_set_id: binding_set_id,
          binding_set_version: version,
          metadata: metadata,
          activated_at: activated_at
        })

      Multi.new()
      |> Multi.insert(:activation_row, BindingSetActivationRow.changeset(activation))
      |> Multi.run(:active_basis_row, fn repo, _changes ->
        upsert_active_basis_row(repo, activation)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{active_basis_row: %ActiveBindingSetRow{} = active_basis_row}} ->
          {:ok, ActiveBindingSetRow.to_domain(active_basis_row)}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec activate_binding_set(binary(), binary(), pos_integer(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def activate_binding_set(mission_id, binding_set_id, version, opts \\ [])
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    metadata = Keyword.get(opts, :metadata, %{})
    activated_at = Keyword.get(opts, :activated_at, DateTime.utc_now())

    with {:ok, _binding_set} <- Governance.fetch_binding_set(mission_id, binding_set_id, version) do
      activation =
        BindingSetActivation.new(%{
          mission_id: mission_id,
          binding_set_id: binding_set_id,
          binding_set_version: version,
          metadata: metadata,
          activated_at: activated_at
        })

      Multi.new()
      |> Multi.insert(:activation_row, BindingSetActivationRow.changeset(activation))
      |> Multi.run(:active_basis_row, fn repo, _changes ->
        upsert_active_basis_row(repo, activation)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{active_basis_row: %ActiveBindingSetRow{} = active_basis_row}} ->
          {:ok, ActiveBindingSetRow.to_domain(active_basis_row)}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_active_activation(binary()) :: {:ok, BindingSetActivation.t()} | {:error, term()}
  def fetch_active_activation(mission_id) when is_binary(mission_id) do
    case Repo.get(ActiveBindingSetRow, mission_id) do
      nil ->
        {:error, :no_active_binding_set}

      %ActiveBindingSetRow{} = active_basis_row ->
        {:ok, ActiveBindingSetRow.to_domain(active_basis_row)}
    end
  end

  @spec fetch_active_activation(binary(), binary()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def fetch_active_activation(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    case Repo.get_by(ActiveBindingSetRow,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      nil ->
        {:error, :no_active_binding_set}

      %ActiveBindingSetRow{} = active_basis_row ->
        {:ok, ActiveBindingSetRow.to_domain(active_basis_row)}
    end
  end

  @spec fetch_active_binding_set(binary()) ::
          {:ok, Cadence.ApplicationDispatch.BindingSet.t()} | {:error, term()}
  def fetch_active_binding_set(mission_id) when is_binary(mission_id) do
    with {:ok, %BindingSetActivation{} = activation} <- fetch_active_activation(mission_id) do
      Governance.fetch_binding_set(
        activation.mission_id,
        activation.binding_set_id,
        activation.binding_set_version
      )
    end
  end

  @spec fetch_active_binding_set(binary(), binary()) ::
          {:ok, Cadence.ApplicationDispatch.BindingSet.t()} | {:error, term()}
  def fetch_active_binding_set(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with {:ok, %BindingSetActivation{} = activation} <-
           fetch_active_activation(organization_id, mission_id) do
      Governance.fetch_binding_set(
        organization_id,
        activation.mission_id,
        activation.binding_set_id,
        activation.binding_set_version
      )
    end
  end

  @spec list_activations(binary()) :: [BindingSetActivation.t()]
  def list_activations(mission_id) when is_binary(mission_id) do
    BindingSetActivationRow
    |> where([activation_row], activation_row.mission_id == ^mission_id)
    |> order_by([activation_row],
      desc: activation_row.activated_at,
      desc: activation_row.activation_id
    )
    |> Repo.all()
    |> Enum.map(&BindingSetActivationRow.to_domain/1)
  end

  @spec list_activations(binary(), binary()) :: [BindingSetActivation.t()]
  def list_activations(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    BindingSetActivationRow
    |> where(
      [activation_row],
      activation_row.organization_id == ^organization_id and
        activation_row.mission_id == ^mission_id
    )
    |> order_by([activation_row],
      desc: activation_row.activated_at,
      desc: activation_row.activation_id
    )
    |> Repo.all()
    |> Enum.map(&BindingSetActivationRow.to_domain/1)
  end

  defp upsert_active_basis_row(repo, %BindingSetActivation{} = activation) do
    changeset = ActiveBindingSetRow.changeset(activation)

    case repo.insert(
           changeset,
           on_conflict: [
             set: [
               activation_id: activation.activation_id,
               binding_set_id: activation.binding_set_id,
               binding_set_version: activation.binding_set_version,
               metadata: ActiveBindingSetRow.metadata_document(activation.metadata),
               activated_at: activation.activated_at
             ]
           ],
           conflict_target: [:mission_id]
         ) do
      {:ok, %ActiveBindingSetRow{} = active_basis_row} ->
        {:ok, active_basis_row}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
