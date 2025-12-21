defmodule Cadence.Domain.Procedures.Entities.ProcedureVersion do
  @moduledoc """
  Pure domain entity representing a version of a procedure.

  Procedure versions go through an approval workflow before they can be executed.
  Each version is immutable once submitted - changes require a new version.

  ## Approval Workflow

  1. Author creates version in `:draft` status
  2. Author submits for review (`:submitted`)
  3. Reviewers can approve or reject
  4. Approved versions can be executed
  5. When a new version is approved, old versions are deprecated

  ## Usage

      # Create a new version
      {:ok, version} = ProcedureVersion.new(%{
        procedure_id: "proc-uuid",
        version_number: 2,
        author_id: "user-uuid",
        steps: steps_definition,
        parameters: parameter_schema
      })

      # Submit for review
      {:ok, submitted} = ProcedureVersion.submit(version)

      # Approve (with required approvals)
      {:ok, approved} = ProcedureVersion.approve(submitted, [approval1, approval2])

      # Or reject
      {:ok, rejected} = ProcedureVersion.reject(submitted, "reviewer-uuid", "Needs more detail")
  """

  alias Cadence.Domain.Procedures.ValueObjects.VersionStatus

  @type approval :: %{
          user_id: String.t(),
          approved_at: DateTime.t(),
          comment: String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          procedure_id: String.t(),
          version_number: pos_integer(),
          status: VersionStatus.t(),
          author_id: String.t(),
          steps: map(),
          parameters: map(),
          description: String.t() | nil,
          change_summary: String.t() | nil,
          approvals: [approval()],
          required_approvals: non_neg_integer(),
          submitted_at: DateTime.t() | nil,
          approved_at: DateTime.t() | nil,
          rejected_at: DateTime.t() | nil,
          rejected_by_id: String.t() | nil,
          rejection_reason: String.t() | nil,
          deprecated_at: DateTime.t() | nil,
          created_at: DateTime.t() | nil
        }

  @enforce_keys [:procedure_id, :version_number, :author_id, :steps]

  defstruct [
    :id,
    :procedure_id,
    :version_number,
    :status,
    :author_id,
    :steps,
    :description,
    :change_summary,
    :submitted_at,
    :approved_at,
    :rejected_at,
    :rejected_by_id,
    :rejection_reason,
    :deprecated_at,
    :created_at,
    parameters: %{},
    approvals: [],
    required_approvals: 1
  ]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new procedure version.

  ## Required Attributes

  - `:procedure_id` - Parent procedure ID
  - `:version_number` - Version number (must be positive)
  - `:author_id` - User who created this version
  - `:steps` - Step definitions (DAG structure)

  ## Optional Attributes

  - `:id` - UUID (generated if not provided)
  - `:parameters` - Parameter schema for execution
  - `:description` - Description of this version
  - `:change_summary` - What changed from previous version
  - `:required_approvals` - Number of approvals needed (default: 1)
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_version_number(attrs),
         :ok <- validate_steps(attrs) do
      version = %__MODULE__{
        id: Map.get(attrs, :id),
        procedure_id: Map.fetch!(attrs, :procedure_id),
        version_number: Map.fetch!(attrs, :version_number),
        status: VersionStatus.initial(),
        author_id: Map.fetch!(attrs, :author_id),
        steps: Map.fetch!(attrs, :steps),
        parameters: Map.get(attrs, :parameters, %{}),
        description: Map.get(attrs, :description),
        change_summary: Map.get(attrs, :change_summary),
        required_approvals: Map.get(attrs, :required_approvals, 1),
        approvals: [],
        created_at: DateTime.utc_now()
      }

      {:ok, version}
    end
  end

  # ===========================================================================
  # Workflow Transitions
  # ===========================================================================

  @doc """
  Submits the version for review.

  Transitions from `:draft` to `:submitted`.
  """
  @spec submit(t()) :: {:ok, t()} | {:error, term()}
  def submit(%__MODULE__{status: status} = version) do
    with :ok <- VersionStatus.validate_transition(status, :submitted) do
      {:ok,
       %{
         version
         | status: :submitted,
           submitted_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Adds an approval to the version.

  If enough approvals are collected, transitions to `:approved`.
  """
  @spec add_approval(t(), String.t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def add_approval(version, user_id, comment \\ nil)

  def add_approval(%__MODULE__{status: :submitted} = version, user_id, comment) do
    if already_approved_by?(version, user_id) do
      {:error, :already_approved}
    else
      approval = %{
        user_id: user_id,
        approved_at: DateTime.utc_now(),
        comment: comment
      }

      version = %{version | approvals: [approval | version.approvals]}

      # Check if we have enough approvals
      if length(version.approvals) >= version.required_approvals do
        {:ok, %{version | status: :approved, approved_at: DateTime.utc_now()}}
      else
        {:ok, version}
      end
    end
  end

  def add_approval(%__MODULE__{status: status}, _user_id, _comment) do
    {:error, {:cannot_approve, status}}
  end

  @doc """
  Approves the version immediately (bypassing approval count).

  Use when a single authorized approver can approve regardless of requirements.
  """
  @spec approve(t()) :: {:ok, t()} | {:error, term()}
  def approve(%__MODULE__{status: status} = version) do
    with :ok <- VersionStatus.validate_transition(status, :approved) do
      {:ok,
       %{
         version
         | status: :approved,
           approved_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Rejects the version.

  Records who rejected it and why.
  """
  @spec reject(t(), String.t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def reject(%__MODULE__{status: status} = version, user_id, reason \\ nil) do
    with :ok <- VersionStatus.validate_transition(status, :rejected) do
      {:ok,
       %{
         version
         | status: :rejected,
           rejected_at: DateTime.utc_now(),
           rejected_by_id: user_id,
           rejection_reason: reason
       }}
    end
  end

  @doc """
  Withdraws the version (author cancels submission).
  """
  @spec withdraw(t()) :: {:ok, t()} | {:error, term()}
  def withdraw(%__MODULE__{status: status} = version) do
    with :ok <- VersionStatus.validate_transition(status, :withdrawn) do
      {:ok, %{version | status: :withdrawn}}
    end
  end

  @doc """
  Deprecates the version (superseded by newer version).
  """
  @spec deprecate(t()) :: {:ok, t()} | {:error, term()}
  def deprecate(%__MODULE__{status: status} = version) do
    with :ok <- VersionStatus.validate_transition(status, :deprecated) do
      {:ok,
       %{
         version
         | status: :deprecated,
           deprecated_at: DateTime.utc_now()
       }}
    end
  end

  # ===========================================================================
  # Draft Editing
  # ===========================================================================

  @doc """
  Updates the steps of a draft version.

  Only allowed when status is `:draft`.
  """
  @spec update_steps(t(), map()) :: {:ok, t()} | {:error, term()}
  def update_steps(%__MODULE__{status: :draft} = version, steps) do
    with :ok <- validate_steps(%{steps: steps}) do
      {:ok, %{version | steps: steps}}
    end
  end

  def update_steps(%__MODULE__{status: status}, _steps) do
    {:error, {:not_editable, status}}
  end

  @doc """
  Updates the parameters of a draft version.
  """
  @spec update_parameters(t(), map()) :: {:ok, t()} | {:error, term()}
  def update_parameters(%__MODULE__{status: :draft} = version, parameters) do
    {:ok, %{version | parameters: parameters}}
  end

  def update_parameters(%__MODULE__{status: status}, _parameters) do
    {:error, {:not_editable, status}}
  end

  @doc """
  Updates the description of a draft version.
  """
  @spec update_description(t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def update_description(%__MODULE__{status: :draft} = version, description) do
    {:ok, %{version | description: description}}
  end

  def update_description(%__MODULE__{status: status}, _description) do
    {:error, {:not_editable, status}}
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Returns true if the version can be executed.
  """
  @spec executable?(t()) :: boolean()
  def executable?(%__MODULE__{status: status}) do
    VersionStatus.executable?(status)
  end

  @doc """
  Returns true if the version can be edited.
  """
  @spec editable?(t()) :: boolean()
  def editable?(%__MODULE__{status: status}) do
    VersionStatus.editable?(status)
  end

  @doc """
  Returns true if the version is pending review.
  """
  @spec pending_review?(t()) :: boolean()
  def pending_review?(%__MODULE__{status: status}) do
    VersionStatus.pending_review?(status)
  end

  @doc """
  Returns the number of approvals still needed.
  """
  @spec approvals_needed(t()) :: non_neg_integer()
  def approvals_needed(%__MODULE__{approvals: approvals, required_approvals: required}) do
    max(0, required - length(approvals))
  end

  @doc """
  Returns true if the user has already approved this version.
  """
  @spec already_approved_by?(t(), String.t()) :: boolean()
  def already_approved_by?(%__MODULE__{approvals: approvals}, user_id) do
    Enum.any?(approvals, fn a -> a.user_id == user_id end)
  end

  @doc """
  Returns true if the user authored this version.
  """
  @spec authored_by?(t(), String.t()) :: boolean()
  def authored_by?(%__MODULE__{author_id: author_id}, user_id) do
    author_id == user_id
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @required_fields [:procedure_id, :version_number, :author_id, :steps]

  defp validate_required(attrs) do
    missing =
      @required_fields
      |> Enum.filter(fn field -> is_nil(Map.get(attrs, field)) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required, missing}}
    end
  end

  defp validate_version_number(%{version_number: v}) when is_integer(v) and v > 0, do: :ok
  defp validate_version_number(%{version_number: _}), do: {:error, :invalid_version_number}
  defp validate_version_number(_), do: :ok

  defp validate_steps(%{steps: steps}) when is_map(steps) and map_size(steps) > 0, do: :ok
  defp validate_steps(%{steps: _}), do: {:error, :invalid_steps}
  defp validate_steps(_), do: :ok
end
