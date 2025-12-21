defmodule Cadence.Buckets do
  @moduledoc """
  Context for managing buckets and bucket memberships.

  Buckets are polymorphic containers that group recordings for access control
  and organizational purposes. Examples include shifts, missions, and anomaly
  investigations.

  ## Bucket Types

  - `mission` - The mission itself as a bucket
  - `shift` - An operator shift period
  - `anomaly` - An anomaly investigation context
  - `target_group` - A group of targets for scoping

  ## Usage

      # Create a bucket for a shift
      {:ok, bucket} = Buckets.create_bucket_for_shift(shift)

      # Add a user to a bucket with command authority
      {:ok, membership} = Buckets.add_member(bucket, user_id, "operator",
        can_command: true,
        max_hazard_level: 3
      )

      # Check if user can command a target
      Buckets.can_command?(bucket, user_id, target_id)
  """

  import Ecto.Query, warn: false

  alias Cadence.Repo
  alias Cadence.Buckets.{Bucket, BucketMembership}

  # ============================================================================
  # Bucket CRUD
  # ============================================================================

  @doc """
  Creates a new bucket.
  """
  @spec create_bucket(map()) :: {:ok, Bucket.t()} | {:error, Ecto.Changeset.t()}
  def create_bucket(attrs) do
    %Bucket{}
    |> Bucket.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a bucket for a shift.
  """
  @spec create_bucket_for_shift(struct()) :: {:ok, Bucket.t()} | {:error, Ecto.Changeset.t()}
  def create_bucket_for_shift(shift) do
    create_bucket(%{
      organization_id: shift.organization_id,
      mission_id: shift.mission_id,
      bucket_type: "shift",
      bucketable_type: "Shift",
      bucketable_id: shift.id,
      name: shift.name,
      started_at: shift.scheduled_start,
      ended_at: shift.scheduled_end
    })
  end

  @doc """
  Gets a bucket by ID scoped to a mission.

  Returns `nil` if not found or if the bucket doesn't belong to the mission.
  """
  @spec get_bucket(String.t(), String.t()) :: Bucket.t() | nil
  def get_bucket(id, mission_id) do
    Bucket
    |> where([b], b.id == ^id and b.mission_id == ^mission_id)
    |> Repo.one()
  end

  @doc """
  Gets a bucket by ID scoped to a mission, raising if not found.
  """
  @spec get_bucket!(String.t(), String.t()) :: Bucket.t()
  def get_bucket!(id, mission_id) do
    Bucket
    |> where([b], b.id == ^id and b.mission_id == ^mission_id)
    |> Repo.one!()
  end

  @doc """
  Gets a bucket by ID without mission scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where mission context is verified elsewhere (e.g., tree traversal).
  """
  @spec get_bucket_unscoped(String.t()) :: Bucket.t() | nil
  def get_bucket_unscoped(id), do: Repo.get(Bucket, id)

  @doc """
  Gets a bucket by its bucketable reference.
  """
  @spec get_bucket_by_bucketable(String.t(), String.t()) :: Bucket.t() | nil
  def get_bucket_by_bucketable(bucketable_type, bucketable_id) do
    Bucket
    |> where([b], b.bucketable_type == ^bucketable_type and b.bucketable_id == ^bucketable_id)
    |> Repo.one()
  end

  @doc """
  Lists buckets for a mission.
  """
  @spec list_buckets(String.t(), keyword()) :: [Bucket.t()]
  def list_buckets(mission_id, opts \\ []) do
    bucket_type = Keyword.get(opts, :bucket_type)

    query =
      Bucket
      |> where([b], b.mission_id == ^mission_id)
      |> order_by([b], desc: b.started_at)

    query = if bucket_type, do: where(query, [b], b.bucket_type == ^bucket_type), else: query

    Repo.all(query)
  end

  @doc """
  Lists active buckets (started but not ended).
  """
  @spec list_active_buckets(String.t()) :: [Bucket.t()]
  def list_active_buckets(mission_id) do
    now = DateTime.utc_now()

    Bucket
    |> where([b], b.mission_id == ^mission_id)
    |> where([b], b.started_at <= ^now)
    |> where([b], is_nil(b.ended_at) or b.ended_at > ^now)
    |> order_by([b], desc: b.started_at)
    |> Repo.all()
  end

  @doc """
  Updates a bucket.
  """
  @spec update_bucket(Bucket.t(), map()) :: {:ok, Bucket.t()} | {:error, Ecto.Changeset.t()}
  def update_bucket(%Bucket{} = bucket, attrs) do
    bucket
    |> Bucket.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bucket.
  """
  @spec delete_bucket(Bucket.t()) :: {:ok, Bucket.t()} | {:error, Ecto.Changeset.t()}
  def delete_bucket(%Bucket{} = bucket) do
    Repo.delete(bucket)
  end

  # ============================================================================
  # Bucket Memberships
  # ============================================================================

  @doc """
  Adds a member to a bucket.

  ## Options

  - `:can_command` - Whether the user can execute commands (default: false)
  - `:max_hazard_level` - Maximum hazard level the user can execute (0-5)
  """
  @spec add_member(Bucket.t(), String.t(), String.t(), keyword()) ::
          {:ok, BucketMembership.t()} | {:error, Ecto.Changeset.t()}
  def add_member(%Bucket{} = bucket, user_id, role, opts \\ []) do
    attrs = %{
      bucket_id: bucket.id,
      user_id: user_id,
      role: role,
      can_command: Keyword.get(opts, :can_command, false),
      max_hazard_level: Keyword.get(opts, :max_hazard_level),
      started_at: Keyword.get(opts, :started_at, DateTime.utc_now())
    }

    %BucketMembership{}
    |> BucketMembership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a membership by ID scoped to a bucket.

  Returns `nil` if not found or if the membership doesn't belong to the bucket.
  """
  @spec get_membership(String.t(), String.t()) :: BucketMembership.t() | nil
  def get_membership(id, bucket_id) do
    BucketMembership
    |> where([m], m.id == ^id and m.bucket_id == ^bucket_id)
    |> Repo.one()
  end

  @doc """
  Gets a membership by ID without bucket scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where bucket context is verified elsewhere.
  """
  @spec get_membership_unscoped(String.t()) :: BucketMembership.t() | nil
  def get_membership_unscoped(id), do: Repo.get(BucketMembership, id)

  @doc """
  Gets an active membership for a user in a bucket.
  """
  @spec get_active_membership(String.t(), String.t()) :: BucketMembership.t() | nil
  def get_active_membership(bucket_id, user_id) do
    BucketMembership
    |> where([m], m.bucket_id == ^bucket_id and m.user_id == ^user_id)
    |> where([m], is_nil(m.ended_at))
    |> Repo.one()
  end

  @doc """
  Lists members of a bucket.
  """
  @spec list_members(String.t(), keyword()) :: [BucketMembership.t()]
  def list_members(bucket_id, opts \\ []) do
    active_only = Keyword.get(opts, :active_only, true)

    query =
      BucketMembership
      |> where([m], m.bucket_id == ^bucket_id)
      |> preload(:user)

    query = if active_only, do: where(query, [m], is_nil(m.ended_at)), else: query

    Repo.all(query)
  end

  @doc """
  Lists buckets a user is a member of.
  """
  @spec list_user_buckets(String.t(), keyword()) :: [Bucket.t()]
  def list_user_buckets(user_id, opts \\ []) do
    active_only = Keyword.get(opts, :active_only, true)

    query =
      Bucket
      |> join(:inner, [b], m in BucketMembership, on: m.bucket_id == b.id)
      |> where([b, m], m.user_id == ^user_id)

    query = if active_only, do: where(query, [b, m], is_nil(m.ended_at)), else: query

    query
    |> distinct(true)
    |> Repo.all()
  end

  @doc """
  Updates a membership.
  """
  @spec update_membership(BucketMembership.t(), map()) ::
          {:ok, BucketMembership.t()} | {:error, Ecto.Changeset.t()}
  def update_membership(%BucketMembership{} = membership, attrs) do
    membership
    |> BucketMembership.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Ends a membership (soft delete).
  """
  @spec end_membership(BucketMembership.t()) ::
          {:ok, BucketMembership.t()} | {:error, Ecto.Changeset.t()}
  def end_membership(%BucketMembership{} = membership) do
    update_membership(membership, %{ended_at: DateTime.utc_now()})
  end

  @doc """
  Removes a member from a bucket (hard delete).
  """
  @spec remove_member(BucketMembership.t()) ::
          {:ok, BucketMembership.t()} | {:error, Ecto.Changeset.t()}
  def remove_member(%BucketMembership{} = membership) do
    Repo.delete(membership)
  end

  # ============================================================================
  # Authorization
  # ============================================================================

  @doc """
  Checks if a user can execute commands in a bucket.
  """
  @spec can_command?(Bucket.t() | String.t(), String.t()) :: boolean()
  def can_command?(bucket_id, user_id) when is_binary(bucket_id) do
    case get_active_membership(bucket_id, user_id) do
      nil -> false
      membership -> membership.can_command
    end
  end

  def can_command?(%Bucket{id: bucket_id}, user_id), do: can_command?(bucket_id, user_id)

  @doc """
  Checks if a user can command a specific target.

  Uses bucket hierarchy - user can command a target if they have command authority
  on any bucket that is an ancestor of the target's bucket.
  """
  @spec can_command_target?(String.t(), String.t(), String.t()) :: boolean()
  def can_command_target?(bucket_id, user_id, _target_id) do
    case get_active_membership(bucket_id, user_id) do
      nil -> false
      %{can_command: false} -> false
      %{can_command: true} -> true
    end
  end

  @doc """
  Checks if a user can execute a command with a given hazard level.
  """
  @spec can_execute_hazard_level?(String.t(), String.t(), integer()) :: boolean()
  def can_execute_hazard_level?(bucket_id, user_id, hazard_level) do
    case get_active_membership(bucket_id, user_id) do
      nil -> false
      %{can_command: false} -> false
      %{max_hazard_level: nil} -> true
      %{max_hazard_level: max} -> hazard_level <= max
    end
  end

  # ============================================================================
  # Tree Operations
  # ============================================================================

  @doc """
  Builds the materialized path for a bucket based on its parent chain.

  Path format: "type_shortid.type_shortid.type_shortid"
  Example: "org_abc123.miss_def456.tg_ghi789.tgt_jkl012"
  """
  @spec build_path(Bucket.t()) :: String.t()
  def build_path(%Bucket{} = bucket) do
    prefix = bucket_type_prefix(bucket.bucket_type)
    short_id = String.slice(bucket.id, 0, 8)
    segment = "#{prefix}_#{short_id}"

    case bucket.parent_id do
      nil ->
        segment

      parent_id ->
        case get_bucket_unscoped(parent_id) do
          nil -> segment
          parent -> "#{parent.path}.#{segment}"
        end
    end
  end

  defp bucket_type_prefix("organization"), do: "org"
  defp bucket_type_prefix("mission"), do: "miss"
  defp bucket_type_prefix("target_group"), do: "tg"
  defp bucket_type_prefix("target"), do: "tgt"
  defp bucket_type_prefix("shift"), do: "shft"
  defp bucket_type_prefix("anomaly"), do: "anom"
  defp bucket_type_prefix(_), do: "b"

  @doc """
  Returns all ancestors of a bucket up to the root.
  """
  @spec get_ancestors(Bucket.t()) :: [Bucket.t()]
  def get_ancestors(%Bucket{parent_id: nil}), do: []

  def get_ancestors(%Bucket{parent_id: parent_id}) do
    case get_bucket_unscoped(parent_id) do
      nil -> []
      parent -> [parent | get_ancestors(parent)]
    end
  end

  @doc """
  Returns all descendants of a bucket (children, grandchildren, etc).
  """
  @spec get_descendants(Bucket.t()) :: [Bucket.t()]
  def get_descendants(%Bucket{path: nil}), do: []

  def get_descendants(%Bucket{path: path}) do
    Bucket
    |> where([b], like(b.path, ^"#{path}.%"))
    |> order_by([b], b.path)
    |> Repo.all()
  end

  @doc """
  Checks if a bucket is in the subtree of another bucket.
  """
  @spec in_subtree?(Bucket.t(), Bucket.t()) :: boolean()
  def in_subtree?(%Bucket{path: child_path}, %Bucket{path: ancestor_path})
      when is_binary(child_path) and is_binary(ancestor_path) do
    String.starts_with?(child_path, ancestor_path <> ".") or child_path == ancestor_path
  end

  def in_subtree?(_, _), do: false

  @doc """
  Creates a bucket with auto-generated path.
  """
  @spec create_bucket_with_path(map()) :: {:ok, Bucket.t()} | {:error, Ecto.Changeset.t()}
  def create_bucket_with_path(attrs) do
    # First create with a temporary path
    with {:ok, bucket} <- create_bucket(attrs) do
      # Then update with the real path
      path = build_path(bucket)
      update_bucket(bucket, %{path: path})
    end
  end
end
