defmodule Cadence.Shifts do
  @moduledoc """
  Context for managing operator shifts.

  Shifts represent scheduled work periods for operators. Each shift automatically
  creates a corresponding bucket for access control and recording scoping.

  ## Lifecycle

  1. **Create** - Shift is scheduled with start/end times
  2. **Start** - Shift becomes active (actual_start set)
  3. **End** - Shift completes (actual_end set)
  4. **Cancel** - Shift is cancelled before completion

  ## Usage

      # Schedule a shift
      {:ok, shift} = Shifts.create_shift(%{
        organization_id: org_id,
        mission_id: mission_id,
        name: "Alpha",
        shift_type: "operational",
        scheduled_start: ~U[2025-01-15 08:00:00Z],
        scheduled_end: ~U[2025-01-15 16:00:00Z]
      })

      # Start the shift
      {:ok, shift} = Shifts.start_shift(shift)

      # Add operators
      {:ok, _} = Shifts.add_operator(shift, user_id, "operator",
        can_command: true,
        max_hazard_level: 3
      )

      # End the shift
      {:ok, shift} = Shifts.end_shift(shift)
  """

  import Ecto.Query, warn: false

  alias Cadence.Repo
  alias Cadence.Shifts.Shift
  alias Cadence.Buckets

  # ============================================================================
  # Shift CRUD
  # ============================================================================

  @doc """
  Creates a new shift and its associated bucket.
  """
  @spec create_shift(map()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def create_shift(attrs) do
    Repo.transaction(fn ->
      with {:ok, shift} <- do_create_shift(attrs),
           {:ok, _bucket} <- Buckets.create_bucket_for_shift(shift) do
        shift
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_create_shift(attrs) do
    %Shift{}
    |> Shift.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a shift by ID.
  """
  @spec get_shift(String.t()) :: Shift.t() | nil
  def get_shift(id), do: Repo.get(Shift, id)

  @doc """
  Gets a shift by ID, raising if not found.
  """
  @spec get_shift!(String.t()) :: Shift.t()
  def get_shift!(id), do: Repo.get!(Shift, id)

  @doc """
  Lists shifts for a mission.

  ## Options

  - `:status` - Filter by status
  - `:from` - Filter shifts starting after this time
  - `:to` - Filter shifts starting before this time
  - `:limit` - Maximum number of results
  """
  @spec list_shifts(String.t(), keyword()) :: [Shift.t()]
  def list_shifts(mission_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)
    limit = Keyword.get(opts, :limit)

    query =
      Shift
      |> where([s], s.mission_id == ^mission_id)
      |> order_by([s], desc: s.scheduled_start)

    query = if status, do: where(query, [s], s.status == ^status), else: query
    query = if from, do: where(query, [s], s.scheduled_start >= ^from), else: query
    query = if to, do: where(query, [s], s.scheduled_start <= ^to), else: query
    query = if limit, do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  @doc """
  Lists currently active shifts for a mission.
  """
  @spec list_active_shifts(String.t()) :: [Shift.t()]
  def list_active_shifts(mission_id) do
    list_shifts(mission_id, status: "active")
  end

  @doc """
  Lists upcoming scheduled shifts for a mission.
  """
  @spec list_upcoming_shifts(String.t(), keyword()) :: [Shift.t()]
  def list_upcoming_shifts(mission_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    now = DateTime.utc_now()

    Shift
    |> where([s], s.mission_id == ^mission_id)
    |> where([s], s.status == "scheduled")
    |> where([s], s.scheduled_start > ^now)
    |> order_by([s], asc: s.scheduled_start)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets the current active shift for a mission, if any.
  """
  @spec get_current_shift(String.t()) :: Shift.t() | nil
  def get_current_shift(mission_id) do
    Shift
    |> where([s], s.mission_id == ^mission_id)
    |> where([s], s.status == "active")
    |> order_by([s], desc: s.actual_start)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Updates a shift.
  """
  @spec update_shift(Shift.t(), map()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def update_shift(%Shift{} = shift, attrs) do
    shift
    |> Shift.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a shift and its associated bucket.
  """
  @spec delete_shift(Shift.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def delete_shift(%Shift{} = shift) do
    Repo.transaction(fn ->
      # Delete associated bucket first
      case Buckets.get_bucket_by_bucketable("Shift", shift.id) do
        nil -> :ok
        bucket -> Buckets.delete_bucket(bucket)
      end

      case Repo.delete(shift) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # ============================================================================
  # Shift Lifecycle
  # ============================================================================

  @doc """
  Starts a shift.

  Sets the actual start time and changes status to active.
  """
  @spec start_shift(Shift.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def start_shift(%Shift{status: "scheduled"} = shift) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      with {:ok, updated} <- update_shift(shift, %{status: "active", actual_start: now}),
           {:ok, _bucket} <- update_shift_bucket(updated) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def start_shift(%Shift{status: status}) do
    {:error, {:invalid_status, status}}
  end

  @doc """
  Ends a shift.

  Sets the actual end time and changes status to completed.
  """
  @spec end_shift(Shift.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def end_shift(%Shift{status: "active"} = shift) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      with {:ok, updated} <- update_shift(shift, %{status: "completed", actual_end: now}),
           {:ok, _bucket} <- update_shift_bucket(updated) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def end_shift(%Shift{status: status}) do
    {:error, {:invalid_status, status}}
  end

  @doc """
  Cancels a shift.
  """
  @spec cancel_shift(Shift.t()) :: {:ok, Shift.t()} | {:error, Ecto.Changeset.t()}
  def cancel_shift(%Shift{status: status} = shift) when status in ["scheduled", "active"] do
    update_shift(shift, %{status: "cancelled"})
  end

  def cancel_shift(%Shift{status: status}) do
    {:error, {:invalid_status, status}}
  end

  # Updates the bucket times when shift status changes
  defp update_shift_bucket(%Shift{} = shift) do
    case Buckets.get_bucket_by_bucketable("Shift", shift.id) do
      nil ->
        {:ok, nil}

      bucket ->
        Buckets.update_bucket(bucket, %{
          started_at: shift.actual_start || shift.scheduled_start,
          ended_at: shift.actual_end || shift.scheduled_end
        })
    end
  end

  # ============================================================================
  # Operator Management
  # ============================================================================

  @doc """
  Adds an operator to a shift.

  This creates a bucket membership for the shift's bucket.

  ## Options

  - `:can_command` - Whether the operator can execute commands (default: true for operators)
  - `:target_group_ids` - List of target group IDs the operator can command
  - `:max_hazard_level` - Maximum hazard level the operator can execute
  """
  @spec add_operator(Shift.t(), String.t(), String.t(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def add_operator(%Shift{} = shift, user_id, role \\ "operator", opts \\ []) do
    # Default to can_command for operators
    opts =
      if role == "operator" and not Keyword.has_key?(opts, :can_command) do
        Keyword.put(opts, :can_command, true)
      else
        opts
      end

    case Buckets.get_bucket_by_bucketable("Shift", shift.id) do
      nil ->
        {:error, :bucket_not_found}

      bucket ->
        Buckets.add_member(bucket, user_id, role, opts)
    end
  end

  @doc """
  Lists operators assigned to a shift.
  """
  @spec list_operators(Shift.t(), keyword()) :: [struct()]
  def list_operators(%Shift{} = shift, opts \\ []) do
    case Buckets.get_bucket_by_bucketable("Shift", shift.id) do
      nil -> []
      bucket -> Buckets.list_members(bucket.id, opts)
    end
  end

  @doc """
  Removes an operator from a shift.
  """
  @spec remove_operator(Shift.t(), String.t()) :: {:ok, struct()} | {:error, term()}
  def remove_operator(%Shift{} = shift, user_id) do
    with bucket when not is_nil(bucket) <- Buckets.get_bucket_by_bucketable("Shift", shift.id),
         membership when not is_nil(membership) <- Buckets.get_active_membership(bucket.id, user_id) do
      Buckets.end_membership(membership)
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets the bucket for a shift.
  """
  @spec get_shift_bucket(Shift.t()) :: struct() | nil
  def get_shift_bucket(%Shift{} = shift) do
    Buckets.get_bucket_by_bucketable("Shift", shift.id)
  end
end
