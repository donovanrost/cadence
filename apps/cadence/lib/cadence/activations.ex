defmodule Cadence.Activations do
  @moduledoc """
  Durable activation control plane for mission-scoped binding-set bases.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Activations.{
    ActiveBindingSetRow,
    BindingSetActivation,
    BindingSetActivationRow
  }

  alias Cadence.Activations.Facts

  alias Cadence.Governance
  alias Cadence.Missions
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Platform.EventBus
  alias Cadence.Repo

  @doc false
  @spec record_binding_set_activation(binary(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def record_binding_set_activation(organization_id, mission_id, binding_set_id, version, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(binding_set_id) and
             is_integer(version) and version > 0 and is_list(opts) do
    with {:ok, _mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, _content_hash} <- Keyword.fetch(opts, :binding_set_content_sha256) do
      persist_activation(
        %{
          organization_id: organization_id,
          mission_id: mission_id,
          activation_request_id: Keyword.get(opts, :activation_request_id),
          binding_set_id: binding_set_id,
          binding_set_version: version,
          binding_set_content_sha256: Keyword.fetch!(opts, :binding_set_content_sha256),
          metadata: Keyword.get(opts, :metadata, %{}),
          activated_at: Keyword.get(opts, :activated_at, DateTime.utc_now())
        },
        Keyword.get(opts, :event_bus, EventBus)
      )
    end
  end

  @doc false
  @spec record_binding_set_activation(binary(), binary(), pos_integer(), keyword()) ::
          {:ok, BindingSetActivation.t()} | {:error, term()}
  def record_binding_set_activation(mission_id, binding_set_id, version, opts)
      when is_binary(mission_id) and is_binary(binding_set_id) and is_integer(version) and
             version > 0 and is_list(opts) do
    with {:ok, _content_hash} <- Keyword.fetch(opts, :binding_set_content_sha256) do
      persist_activation(
        %{
          mission_id: mission_id,
          activation_request_id: Keyword.get(opts, :activation_request_id),
          binding_set_id: binding_set_id,
          binding_set_version: version,
          binding_set_content_sha256: Keyword.fetch!(opts, :binding_set_content_sha256),
          metadata: Keyword.get(opts, :metadata, %{}),
          activated_at: Keyword.get(opts, :activated_at, DateTime.utc_now())
        },
        Keyword.get(opts, :event_bus, EventBus)
      )
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

  @doc false
  @spec list_active_activations() :: [BindingSetActivation.t()]
  def list_active_activations do
    ActiveBindingSetRow
    |> Repo.all()
    |> Enum.map(&ActiveBindingSetRow.to_domain/1)
  end

  defp upsert_active_basis_row(repo, %BindingSetActivation{} = activation) do
    changeset = ActiveBindingSetRow.changeset(activation)

    case repo.insert(
           changeset,
           on_conflict: [
             set: [
               activation_id: activation.activation_id,
               activation_request_id: activation.activation_request_id,
               generation: activation.generation,
               binding_set_id: activation.binding_set_id,
               binding_set_version: activation.binding_set_version,
               binding_set_content_sha256: activation.binding_set_content_sha256,
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

  defp persist_activation_operational_event(repo, %BindingSetActivation{} = activation) do
    OperationalEvents.persist_event(
      repo,
      OperationalEvent.from_binding_set_activation(activation)
    )
  end

  defp persist_activation(attrs, event_bus) do
    Multi.new()
    |> Multi.run(:generation_lock, fn repo, _changes ->
      acquire_generation_lock(repo, attrs.mission_id)
    end)
    |> Multi.run(:generation, fn repo, _changes ->
      {:ok, next_generation(repo, attrs.mission_id)}
    end)
    |> Multi.run(:activation_record, fn repo, %{generation: generation} ->
      find_or_insert_activation(repo, attrs, generation)
    end)
    |> Multi.run(:active_basis_row, fn repo, %{activation_record: activation_record} ->
      maybe_upsert_active_basis(repo, activation_record)
    end)
    |> Multi.run(:operational_event, fn repo, %{activation_record: activation_record} ->
      maybe_persist_activation_operational_event(repo, activation_record)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{activation_record: %{row: activation_row, inserted?: inserted?}}} ->
        activation = BindingSetActivationRow.to_domain(activation_row)
        if inserted?, do: Facts.publish(event_bus, activation)
        {:ok, activation}

      {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
        {:error, changeset}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp find_or_insert_activation(repo, attrs, generation) do
    case existing_activation(repo, attrs.activation_request_id) do
      %BindingSetActivationRow{} = row ->
        {:ok, %{row: row, inserted?: false}}

      nil ->
        changeset =
          attrs
          |> Map.put(:generation, generation)
          |> BindingSetActivation.new()
          |> BindingSetActivationRow.changeset()

        case repo.insert(changeset) do
          {:ok, row} -> {:ok, %{row: row, inserted?: true}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp existing_activation(_repo, nil), do: nil

  defp existing_activation(repo, activation_request_id) do
    repo.get_by(BindingSetActivationRow, activation_request_id: activation_request_id)
  end

  defp maybe_upsert_active_basis(repo, %{row: row, inserted?: true}) do
    upsert_active_basis_row(repo, BindingSetActivationRow.to_domain(row))
  end

  defp maybe_upsert_active_basis(_repo, %{inserted?: false}), do: {:ok, :unchanged}

  defp maybe_persist_activation_operational_event(repo, %{row: row, inserted?: true}) do
    persist_activation_operational_event(repo, BindingSetActivationRow.to_domain(row))
  end

  defp maybe_persist_activation_operational_event(_repo, %{inserted?: false}),
    do: {:ok, :unchanged}

  defp acquire_generation_lock(repo, mission_id) do
    case SQL.query(repo, "SELECT pg_advisory_xact_lock(hashtext($1))", [mission_id]) do
      {:ok, _result} -> {:ok, :locked}
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_generation(repo, mission_id) do
    BindingSetActivationRow
    |> where([activation], activation.mission_id == ^mission_id)
    |> select([activation], max(activation.generation))
    |> repo.one()
    |> case do
      nil -> 1
      generation -> generation + 1
    end
  end
end
