defmodule Cadence.Application.Procedures.ManageVersions do
  @moduledoc """
  Use case module for managing procedure versions.

  Handles creation and editing of procedure versions in draft status.
  Once a version is submitted for review, use ApprovalWorkflow for
  status changes.

  ## Usage

      # Create new version
      {:ok, version} = ManageVersions.create(%{
        procedure_id: proc_id,
        author_id: user_id,
        steps: %{"step_1" => %{"type" => "command", ...}},
        description: "Initial version"
      })

      # Update draft
      {:ok, version} = ManageVersions.update_steps(version_id, new_steps)
      {:ok, version} = ManageVersions.update_parameters(version_id, new_params)
  """

  alias Cadence.Domain.Procedures.Entities.ProcedureVersion
  alias Cadence.Application.Procedures.ProcedureQueries

  @type version_id :: String.t()
  @type procedure_id :: String.t()

  @type create_attrs :: %{
          required(:procedure_id) => String.t(),
          required(:author_id) => String.t(),
          required(:steps) => map(),
          optional(:parameters) => map(),
          optional(:description) => String.t() | nil,
          optional(:change_summary) => String.t() | nil,
          optional(:required_approvals) => pos_integer()
        }

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :procedure_repository,
      Cadence.Adapters.Persistence.Ecto.Procedures.EctoProcedureRepository
    )
  end

  # Get configured event recorder
  defp recorder do
    Cadence.Ports.Recordings.EventRecorder.impl()
  end

  @doc """
  Creates a new procedure version.

  Automatically assigns the next version number.
  The version starts in `:draft` status.

  ## Parameters

  - `attrs` - Version attributes (see type spec)

  ## Returns

  - `{:ok, version}` - Successfully created
  - `{:error, {:missing_required, fields}}` - Missing required fields
  - `{:error, :invalid_steps}` - Steps map is empty or invalid
  - `{:error, :invalid_version_number}` - Version number not positive
  """
  @spec create(create_attrs()) :: {:ok, ProcedureVersion.t()} | {:error, term()}
  def create(attrs) do
    # Get next version number
    version_number = ProcedureQueries.next_version_number(attrs[:procedure_id])

    entity_attrs = Map.put(attrs, :version_number, version_number)

    with {:ok, version} <- ProcedureVersion.new(entity_attrs),
         {:ok, saved} <- repo().save_version(version) do
      broadcast_created(saved)
      {:ok, saved}
    end
  end

  @doc """
  Creates a new version based on an existing one.

  Copies steps and parameters from the source version,
  incrementing the version number.

  ## Parameters

  - `source_version_id` - UUID of version to copy from
  - `author_id` - UUID of the new version's author
  - `change_summary` - Description of what changed

  ## Returns

  - `{:ok, version}` - Successfully created
  - `{:error, :not_found}` - Source version not found
  """
  @spec create_from(version_id(), String.t(), String.t() | nil) ::
          {:ok, ProcedureVersion.t()} | {:error, term()}
  def create_from(source_version_id, author_id, change_summary \\ nil) do
    with {:ok, source} <- ProcedureQueries.find_version(source_version_id) do
      create(%{
        procedure_id: source.procedure_id,
        author_id: author_id,
        steps: source.steps,
        parameters: source.parameters,
        description: source.description,
        change_summary: change_summary,
        required_approvals: source.required_approvals
      })
    end
  end

  @doc """
  Updates the steps of a draft version.

  Only allowed when version is in `:draft` status.

  ## Parameters

  - `version_id` - UUID of the version
  - `steps` - New steps map (must not be empty)

  ## Returns

  - `{:ok, version}` - Successfully updated
  - `{:error, :not_found}` - Version not found
  - `{:error, {:not_editable, status}}` - Not in draft status
  - `{:error, :invalid_steps}` - Steps map is empty
  """
  @spec update_steps(version_id(), map()) :: {:ok, ProcedureVersion.t()} | {:error, term()}
  def update_steps(version_id, steps) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.update_steps(version, steps),
         {:ok, saved} <- repo().save_version(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Updates the parameters schema of a draft version.

  ## Parameters

  - `version_id` - UUID of the version
  - `parameters` - New parameters schema

  ## Returns

  - `{:ok, version}` - Successfully updated
  - `{:error, :not_found}` - Version not found
  - `{:error, {:not_editable, status}}` - Not in draft status
  """
  @spec update_parameters(version_id(), map()) :: {:ok, ProcedureVersion.t()} | {:error, term()}
  def update_parameters(version_id, parameters) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.update_parameters(version, parameters),
         {:ok, saved} <- repo().save_version(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Updates the description of a draft version.

  ## Parameters

  - `version_id` - UUID of the version
  - `description` - New description

  ## Returns

  - `{:ok, version}` - Successfully updated
  - `{:error, :not_found}` - Version not found
  - `{:error, {:not_editable, status}}` - Not in draft status
  """
  @spec update_description(version_id(), String.t() | nil) ::
          {:ok, ProcedureVersion.t()} | {:error, term()}
  def update_description(version_id, description) do
    with {:ok, version} <- ProcedureQueries.find_version(version_id),
         {:ok, updated} <- ProcedureVersion.update_description(version, description),
         {:ok, saved} <- repo().save_version(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Validates the steps of a version without saving.

  Useful for real-time validation in the editor.

  ## Parameters

  - `steps` - Steps map to validate

  ## Returns

  - `:ok` - Steps are valid
  - `{:error, errors}` - Validation errors
  """
  @spec validate_steps(map()) :: :ok | {:error, term()}
  def validate_steps(steps) when is_map(steps) and map_size(steps) > 0 do
    # TODO: Add DAG validation
    :ok
  end

  def validate_steps(_), do: {:error, :invalid_steps}

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp broadcast_created(%ProcedureVersion{procedure_id: procedure_id} = version) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "procedure:#{procedure_id}:versions",
      {:version_created, version}
    )

    # Record the creation event
    recorder().record(:procedure_version_created, version, version.author_id, %{})
  rescue
    _ -> :ok
  end
end
