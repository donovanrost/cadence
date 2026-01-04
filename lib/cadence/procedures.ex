defmodule Cadence.Procedures do
  @moduledoc """
  The Procedures context.

  Manages procedure definitions, versions, and executions.
  """

  import Ecto.Query

  alias Cadence.Procedures.{
    Parameters,
    Procedure,
    ProcedureExecution,
    ProcedureReview,
    ProcedureReviewComment,
    ProcedureReviewRequest,
    ProcedureReviewThread,
    ProcedureVersion,
    V2
  }

  alias Cadence.Outbox
  alias Cadence.Recordings
  alias Cadence.Repo
  alias Cadence.Settings
  alias Cadence.Targets

  alias Cadence.Recordings.Recordables.{
    ProcedureChangesRequested,
    ProcedureReviewApproved,
    ProcedureReviewCommentAdded,
    ProcedureReviewRequested,
    ProcedureReviewSubmitted,
    ProcedureThreadResolved,
    ProcedureVersionClosed,
    ProcedureVersionCreated,
    ProcedureVersionResubmitted,
    ProcedureVersionWithdrawn
  }

  alias Ecto.Multi

  # ============================================================================
  # Procedures
  # ============================================================================

  @doc """
  Lists all unique tags used in procedures for an organization/mission.
  """
  def list_tags(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)

    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> select([p], p.tags)
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists procedures for an organization, optionally filtered by mission and tags.

  ## Options

  - `:mission_id` - Filter to procedures in this mission
  - `:tags` - Filter to procedures that have ALL specified tags (AND logic)
  """
  def list_procedures(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    tags = Keyword.get(opts, :tags, [])

    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> maybe_filter_by_mission(mission_id)
    |> maybe_filter_by_tags(tags)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  defp maybe_filter_by_mission(query, nil), do: query

  defp maybe_filter_by_mission(query, mission_id) do
    where(query, [p], p.mission_id == ^mission_id or is_nil(p.mission_id))
  end

  defp maybe_filter_by_tags(query, []), do: query

  defp maybe_filter_by_tags(query, tags) when is_list(tags) do
    where(query, [p], fragment("? @> ?", p.tags, ^tags))
  end

  @doc """
  Gets a procedure by ID.
  """
  def get_procedure(id), do: Repo.get(Procedure, id)

  @doc """
  Gets a procedure by ID, raises if not found.
  """
  def get_procedure!(id), do: Repo.get!(Procedure, id)

  @doc """
  Gets a procedure by name within a mission.
  """
  def get_procedure_by_name(organization_id, mission_id, name) do
    Procedure
    |> where([p], p.organization_id == ^organization_id)
    |> where([p], p.mission_id == ^mission_id or is_nil(p.mission_id))
    |> where([p], p.name == ^name)
    |> Repo.one()
  end

  @doc """
  Creates a procedure with an initial draft version.
  """
  def create_procedure(attrs, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    source = Keyword.get(opts, :source, %{"steps" => []})

    Repo.transaction(fn ->
      # Create procedure
      procedure =
        %Procedure{}
        |> Procedure.changeset(attrs)
        |> Repo.insert!()

      # Create initial version
      version_attrs = %{
        procedure_id: procedure.id,
        version_number: 1,
        source: source,
        parameters_schema: Keyword.get(opts, :parameters_schema, %{}),
        allow_hazardous_commands: Keyword.get(opts, :allow_hazardous_commands, false),
        created_by_id: user_id
      }

      version =
        %ProcedureVersion{}
        |> ProcedureVersion.changeset(version_attrs)
        |> Repo.insert!()

      # Update procedure with current version
      procedure
      |> Procedure.changeset(%{current_version_id: version.id})
      |> Repo.update!()
    end)
  end

  @doc """
  Creates a new V2 procedure with initial block-based structure.

  This creates:
  - Procedure record
  - Initial ProcedureVersion (draft, manual execution mode)
  - Default ProcedureSection named "Main"
  - Starter ProcedureStep
  - Welcome text block

  Returns `{:ok, {procedure, version}}` on success.

  ## Options

  - `:user_id` - User creating the procedure (required)
  """
  def create_procedure_v2(attrs, opts \\ []) do
    user_id = Keyword.fetch!(opts, :user_id)

    Repo.transaction(fn ->
      # 1. Create procedure
      procedure_attrs =
        attrs
        |> Map.take([:name, :description, :tags, :organization_id, :mission_id])
        |> Map.put(:type, :dag)

      procedure =
        %Procedure{}
        |> Procedure.changeset(procedure_attrs)
        |> Repo.insert!()

      # 2. Create initial version (empty source - V2 uses sections/steps/blocks)
      version_attrs = %{
        procedure_id: procedure.id,
        version_number: 1,
        source: %{},
        execution_mode: :manual,
        created_by_id: user_id
      }

      version =
        %ProcedureVersion{}
        |> ProcedureVersion.changeset(version_attrs)
        |> Repo.insert!()

      # Update procedure with current version
      procedure =
        procedure
        |> Procedure.changeset(%{current_version_id: version.id})
        |> Repo.update!()

      # 3. Create default section
      {:ok, section} =
        V2.create_section(version.id, %{
          name: "Main",
          position: 0
        })

      # 4. Create starter step
      {:ok, step} =
        V2.create_step(section.id, %{
          name: "start",
          title: "Getting Started",
          position: 0,
          requires_signoff: true
        })

      # 5. Create welcome block
      {:ok, _block} =
        V2.create_block(step.id, %{
          block_type: :text,
          position: 0,
          content: %{"markdown" => "Add your procedure steps here."}
        })

      {procedure, version}
    end)
  end

  @doc """
  Updates a procedure's metadata (not source - use create_version for that).
  """
  def update_procedure(%Procedure{} = procedure, attrs) do
    procedure
    |> Procedure.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a procedure and all its versions/executions.
  """
  def delete_procedure(%Procedure{} = procedure) do
    Repo.delete(procedure)
  end

  # ============================================================================
  # Versions
  # ============================================================================

  @doc """
  Lists versions for a procedure.
  """
  def list_versions(procedure_id) do
    ProcedureVersion
    |> where([v], v.procedure_id == ^procedure_id)
    |> order_by([v], desc: v.version_number)
    |> Repo.all()
  end

  @doc """
  Gets a specific version.
  """
  def get_version(id), do: Repo.get(ProcedureVersion, id)
  def get_version!(id), do: Repo.get!(ProcedureVersion, id)

  @doc """
  Gets the previous version (by version number) for diffing.

  Returns nil if this is the first version.
  """
  def get_previous_version(procedure_id, current_version_number) do
    from(v in ProcedureVersion,
      where: v.procedure_id == ^procedure_id and v.version_number < ^current_version_number,
      order_by: [desc: v.version_number],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets the current approved version for a procedure.
  """
  def get_approved_version(procedure_id) do
    ProcedureVersion
    |> where([v], v.procedure_id == ^procedure_id)
    |> where([v], v.status == :approved)
    |> order_by([v], desc: v.version_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Publishes an approved version, making it the current version of the procedure.

  This sets the procedure's `current_version_id` to point to this version.

  Returns `{:ok, %{procedure: procedure, version: version}}` on success.
  Returns `{:error, reason}` if the version is not approved or doesn't belong to the procedure.
  """
  def publish_version(%Procedure{} = procedure, %ProcedureVersion{} = version, _user_id) do
    cond do
      version.procedure_id != procedure.id ->
        {:error, :version_does_not_belong_to_procedure}

      version.status != :approved ->
        {:error, :version_not_approved}

      true ->
        procedure
        |> Ecto.Changeset.change(%{current_version_id: version.id})
        |> Repo.update()
        |> case do
          {:ok, updated_procedure} ->
            {:ok, %{procedure: updated_procedure, version: version}}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Creates a new version of a procedure.
  """
  def create_version(procedure_or_id, attrs, opts \\ [])

  def create_version(%Procedure{id: procedure_id}, attrs, opts) do
    create_version(procedure_id, attrs, opts)
  end

  def create_version(procedure_id, attrs, opts) when is_binary(procedure_id) do
    procedure = get_procedure!(procedure_id)
    user_id = Keyword.get(opts, :user_id)

    version_number = next_version_number(procedure_id)
    version_attrs = build_version_attrs(attrs, procedure_id, version_number, user_id)
    version_created_attrs = build_version_created_attrs(attrs, procedure_id, version_number)

    Multi.new()
    |> Multi.insert(:version, ProcedureVersion.changeset(%ProcedureVersion{}, version_attrs))
    |> Recordings.append(:created, ProcedureVersionCreated, version_created_attrs, fn %{
                                                                                        version: v
                                                                                      } ->
      version_recording_attrs(procedure, user_id, v.id)
    end)
    |> Repo.transaction()
    |> normalize_version_result()
  end

  defp next_version_number(procedure_id) do
    ProcedureVersion
    |> where([v], v.procedure_id == ^procedure_id)
    |> select([v], max(v.version_number))
    |> Repo.one()
    |> case do
      nil -> 1
      max_version -> max_version + 1
    end
  end

  defp build_version_attrs(attrs, procedure_id, version_number, user_id) do
    attrs
    |> Map.put(:procedure_id, procedure_id)
    |> Map.put(:version_number, version_number)
    |> Map.put_new(:status, :draft)
    |> maybe_put_created_by(user_id)
  end

  defp maybe_put_created_by(attrs, nil), do: attrs
  defp maybe_put_created_by(attrs, user_id), do: Map.put_new(attrs, :created_by_id, user_id)

  defp build_version_created_attrs(attrs, procedure_id, version_number) do
    source_code = get_in(attrs, [:source]) || get_in(attrs, ["source"])

    %{
      procedure_id: procedure_id,
      version_number: version_number,
      source_code: snippet_source(source_code)
    }
  end

  defp snippet_source(source_code) when is_map(source_code) do
    source_code
    |> Jason.encode!()
    |> String.slice(0, 500)
  end

  defp snippet_source(_source_code), do: nil

  defp version_recording_attrs(procedure, user_id, version_id) do
    %{
      organization_id: procedure.organization_id,
      mission_id: procedure.mission_id,
      bucket_id: get_mission_bucket_id(procedure.mission_id),
      aggregate_type: "ProcedureVersion",
      aggregate_id: version_id,
      actor_id: user_id,
      actor_type: if(user_id, do: "user", else: "system"),
      timestamp: DateTime.utc_now()
    }
  end

  defp normalize_version_result({:ok, %{version: version}}), do: {:ok, version}
  defp normalize_version_result({:error, :version, changeset, _}), do: {:error, changeset}
  defp normalize_version_result({:error, _step, changeset, _}), do: {:error, changeset}

  @doc """
  Approves a version.
  """
  def approve_version(%ProcedureVersion{} = version, user_id) do
    Repo.transaction(fn ->
      # Update version status
      updated_version =
        version
        |> ProcedureVersion.approval_changeset(%{
          status: :approved,
          approved_at: DateTime.utc_now(),
          approved_by_id: user_id
        })
        |> Repo.update!()

      # Update procedure's current version
      Procedure
      |> where([p], p.id == ^version.procedure_id)
      |> Repo.update_all(set: [current_version_id: version.id])

      updated_version
    end)
  end

  @doc """
  Deprecates a version.
  """
  def deprecate_version(%ProcedureVersion{} = version) do
    version
    |> ProcedureVersion.approval_changeset(%{status: :deprecated})
    |> Repo.update()
  end

  @doc """
  Creates a new draft version by cloning an existing version.

  This is used when editing an approved version - instead of modifying the
  approved version directly, we create a new draft that inherits all content
  from the source version.

  The new version will have:
  - A new version number (next in sequence)
  - Status of :draft
  - All sections, steps, and blocks copied from the source version

  ## Options

  - `:user_id` - The user creating the new version (sets created_by_id)
  """
  def create_draft_from_version(%ProcedureVersion{} = source_version, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    procedure_id = source_version.procedure_id

    # Calculate next version number
    version_number = next_version_number(procedure_id)

    # Build version attributes from source
    version_attrs = %{
      procedure_id: procedure_id,
      version_number: version_number,
      status: :draft,
      source: source_version.source,
      parameters_schema: source_version.parameters_schema,
      execution_mode: source_version.execution_mode,
      allow_suggested_edits: source_version.allow_suggested_edits,
      allow_hazardous_commands: source_version.allow_hazardous_commands,
      created_by_id: user_id
    }

    Repo.transaction(fn ->
      # 1. Create the new version
      {:ok, new_version} =
        %ProcedureVersion{}
        |> ProcedureVersion.changeset(version_attrs)
        |> Repo.insert()

      # 2. Clone sections, steps, and blocks
      clone_version_content(source_version.id, new_version.id)

      new_version
    end)
  end

  # Clones all sections, steps, and blocks from source version to target version
  defp clone_version_content(source_version_id, target_version_id) do
    # Load source sections with steps and blocks
    source_sections = V2.list_sections_with_steps(source_version_id)

    # Clone each section
    Enum.each(source_sections, fn source_section ->
      # Create new section
      {:ok, new_section} =
        V2.create_section(target_version_id, %{
          name: source_section.name,
          description: source_section.description,
          position: source_section.position,
          collapsed_by_default: source_section.collapsed_by_default
        })

      # Clone each step in the section
      Enum.each(source_section.steps, fn source_step ->
        {:ok, new_step} =
          V2.create_step(new_section.id, %{
            name: source_step.name,
            title: source_step.title,
            position: source_step.position,
            requires_signoff: source_step.requires_signoff,
            required_roles: source_step.required_roles,
            signoff_logic: source_step.signoff_logic,
            depends_on: source_step.depends_on,
            dependency_logic: source_step.dependency_logic,
            condition: source_step.condition,
            on_fail: source_step.on_fail,
            estimated_duration_seconds: source_step.estimated_duration_seconds
          })

        # Clone each block in the step
        Enum.each(source_step.blocks, fn source_block ->
          {:ok, _new_block} =
            V2.create_block(new_step.id, %{
              block_type: source_block.block_type,
              position: source_block.position,
              name: source_block.name,
              label: source_block.label,
              required: source_block.required,
              content: source_block.content
            })
        end)
      end)
    end)
  end

  # ============================================================================
  # Approval Workflow (PR-style Review System)
  # ============================================================================

  @doc """
  Submits a procedure version for review. (draft → in_review)

  Creates an audit event recording the submission and optionally creates
  review requests for specific reviewers.

  ## Options

  - `:reviewer_ids` - List of user IDs to request reviews from
  - `:note` - Optional note explaining the submission
  """
  def submit_for_review(%ProcedureVersion{} = version, user_id, opts \\ []) do
    reviewer_ids = Keyword.get(opts, :reviewer_ids, [])
    note = Keyword.get(opts, :note)

    with :ok <- validate_status(version, :draft) do
      version = Repo.preload(version, :procedure)

      multi =
        Multi.new()
        |> Multi.update(
          :version,
          ProcedureVersion.submit_changeset(version, %{
            status: :in_review,
            submitted_at: DateTime.utc_now(),
            submitted_by_id: user_id
          })
        )
        |> Outbox.append(:outbox, fn %{version: v} ->
          %{
            organization_id: version.procedure.organization_id,
            mission_id: version.procedure.mission_id,
            event_type: "procedure_submitted",
            aggregate_type: "procedure_version",
            aggregate_id: v.id,
            actor_id: user_id,
            actor_type: "user",
            payload: %{
              procedure_id: version.procedure_id,
              procedure_name: version.procedure.name,
              version_number: version.version_number,
              reviewer_ids: reviewer_ids
            }
          }
        end)
        |> Recordings.append(
          :submitted,
          ProcedureReviewSubmitted,
          %{note: note, reviewer_ids: reviewer_ids},
          fn %{version: v} ->
            version_recording_attrs(version.procedure, user_id, v.id)
          end
        )

      # Create review requests for each requested reviewer
      multi =
        reviewer_ids
        |> Enum.with_index()
        |> Enum.reduce(multi, fn {reviewer_id, idx}, acc ->
          Multi.insert(acc, {:review_request, idx}, fn %{version: v} ->
            ProcedureReviewRequest.changeset(%ProcedureReviewRequest{}, %{
              procedure_version_id: v.id,
              requester_id: user_id,
              reviewer_id: reviewer_id,
              status: :pending
            })
          end)
        end)

      # Record individual review requests
      multi =
        reviewer_ids
        |> Enum.with_index()
        |> Enum.reduce(multi, fn {reviewer_id, idx}, acc ->
          Recordings.append(
            acc,
            {:requested, idx},
            ProcedureReviewRequested,
            %{reviewer_id: reviewer_id, message: nil},
            fn %{version: v} ->
              version_recording_attrs(version.procedure, user_id, v.id)
            end
          )
        end)

      multi
      |> Repo.transaction()
      |> case do
        {:ok, %{version: updated}} -> {:ok, updated}
        {:error, _step, changeset, _} -> {:error, changeset}
      end
    end
  end

  @doc """
  Withdraws a submission. (in_review or changes_requested → draft)

  Only the author (submitted_by or created_by) can withdraw, and only if
  the `allow_withdrawal` setting is enabled for the mission.

  Cancels any pending review requests and marks existing reviews as superseded.
  """
  def withdraw_submission(%ProcedureVersion{} = version, user_id) do
    with :ok <- validate_status_in(version, [:in_review, :changes_requested]),
         :ok <- validate_can_withdraw(version, user_id) do
      version = Repo.preload(version, :procedure)

      Repo.transaction(fn ->
        # Cancel pending review requests
        from(rr in ProcedureReviewRequest,
          where: rr.procedure_version_id == ^version.id and rr.status == :pending
        )
        |> Repo.update_all(set: [status: :cancelled])

        # Supersede all active reviews
        from(r in ProcedureReview,
          where: r.procedure_version_id == ^version.id and r.superseded == false
        )
        |> Repo.update_all(set: [superseded: true])

        updated =
          version
          |> ProcedureVersion.withdrawal_changeset(%{})
          |> Repo.update!()

        # Record the withdrawal
        record_version_event(updated, user_id, ProcedureVersionWithdrawn, %{})

        updated
      end)
    end
  end

  @doc """
  Adds a review decision (approve or request_changes) to a version.

  ## Decision Types

  - `:approve` - Approves the version. If approval threshold is met, version
    transitions to :approved status.
  - `:request_changes` - Requests changes. Creates a review thread and
    transitions version to :changes_requested status.

  ## Options

  - `:body` - Review comment (required for request_changes, optional for approve)

  ## Returns

  - `{:ok, %{review: review, version: version}}` on success
  - `{:error, reason}` on failure
  """
  def add_review(%ProcedureVersion{} = version, user_id, decision, opts \\ [])
      when decision in [:approve, :request_changes] do
    body = Keyword.get(opts, :body)
    version = Repo.preload(version, :procedure)

    with :ok <- validate_status_in(version, [:in_review, :changes_requested]),
         :ok <- validate_can_review(version, user_id) do
      Repo.transaction(fn ->
        # Supersede any previous reviews from this user
        from(r in ProcedureReview,
          where:
            r.procedure_version_id == ^version.id and
              r.user_id == ^user_id and
              r.superseded == false
        )
        |> Repo.update_all(set: [superseded: true])

        # Create the new review
        {:ok, review} =
          %ProcedureReview{}
          |> ProcedureReview.changeset(%{
            procedure_version_id: version.id,
            user_id: user_id,
            decision: decision,
            body: body
          })
          |> Repo.insert()

        # Complete any pending review request from this user
        from(rr in ProcedureReviewRequest,
          where:
            rr.procedure_version_id == ^version.id and
              rr.reviewer_id == ^user_id and
              rr.status == :pending
        )
        |> Repo.update_all(set: [status: :completed, completed_at: DateTime.utc_now()])

        # Handle the decision
        {updated_version, thread} = handle_review_decision(version, review, user_id, body)

        # Record the event
        record_review_event(version, updated_version, user_id, decision, body, thread)

        %{review: review, version: updated_version, thread: thread}
      end)
    end
  end

  # Legacy alias for backwards compatibility
  @doc false
  def add_approval(version, user_id, decision, opts \\ []) do
    new_decision =
      case decision do
        :approved -> :approve
        :rejected -> :request_changes
        other -> other
      end

    add_review(version, user_id, new_decision, opts)
  end

  @doc """
  Gets review status summary for a version.

  Returns a map with:
  - `:required` - Number of approvals required
  - `:approved_count` - Number of active approvals
  - `:changes_requested_count` - Number of active change requests
  - `:pending` - Number of approvals still needed
  - `:can_be_approved` - Whether version has enough approvals with no blockers
  - `:is_blocked` - Whether there are unresolved change requests
  - `:reviews` - List of active (non-superseded) reviews with users preloaded
  - `:open_threads` - List of open review threads
  """
  def get_review_status(%ProcedureVersion{} = version) do
    version = Repo.preload(version, [:procedure, reviews: :user, review_threads: :author])
    required = get_required_approvals(version)

    # Get active (non-superseded) reviews
    active_reviews =
      version.reviews
      |> Enum.filter(&(not &1.superseded))

    approved_count = Enum.count(active_reviews, &(&1.decision == :approve))
    changes_requested_count = Enum.count(active_reviews, &(&1.decision == :request_changes))

    # Get open threads (blocking for resubmit)
    open_threads =
      version.review_threads
      |> Enum.filter(&(&1.status == :open))

    %{
      required: required,
      approved_count: approved_count,
      changes_requested_count: changes_requested_count,
      pending: max(0, required - approved_count),
      can_be_approved: approved_count >= required and changes_requested_count == 0,
      is_blocked: changes_requested_count > 0 or length(open_threads) > 0,
      reviews: active_reviews,
      open_threads: open_threads
    }
  end

  # Legacy alias
  @doc false
  def get_approval_status(version), do: get_review_status(version)

  @doc """
  Lists all reviews for a version.

  ## Options

  - `:include_superseded` - Include superseded reviews (default: false)
  """
  def list_reviews(version_id, opts \\ []) do
    include_superseded = Keyword.get(opts, :include_superseded, false)

    query =
      from r in ProcedureReview,
        where: r.procedure_version_id == ^version_id,
        order_by: [desc: r.inserted_at],
        preload: [:user]

    query =
      if include_superseded do
        query
      else
        where(query, [r], r.superseded == false)
      end

    Repo.all(query)
  end

  @doc """
  Lists all audit events for a version.

  Returns recordings for the version aggregate with their recordables loaded.

  ## Options

  - `:limit` - Maximum number of events to return (default: 100)
  """
  def list_version_events(version_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Recordings.list_aggregate_recordings(
      "ProcedureVersion",
      nil,
      Keyword.merge(opts, aggregate_id: version_id, limit: limit)
    )
    |> Recordings.load_recordables_for_recordings()
  end

  # ============================================================================
  # Threading Functions
  # ============================================================================

  @doc """
  Adds a comment to a review thread.

  Anyone with access to the procedure can add comments to existing threads.
  """
  def add_comment(%ProcedureReviewThread{} = thread, user_id, body) do
    thread = Repo.preload(thread, procedure_version: :procedure)

    Repo.transaction(fn ->
      {:ok, comment} =
        %ProcedureReviewComment{}
        |> ProcedureReviewComment.changeset(%{
          thread_id: thread.id,
          user_id: user_id,
          body: body
        })
        |> Repo.insert()

      # Record the event
      record_version_event(
        thread.procedure_version,
        user_id,
        ProcedureReviewCommentAdded,
        %{thread_id: thread.id, body: body}
      )

      comment
    end)
  end

  @doc """
  Resolves a review thread.

  Threads can be resolved by the author or any reviewer.
  """
  def resolve_thread(%ProcedureReviewThread{} = thread, user_id) do
    if thread.status == :resolved do
      {:error, :already_resolved}
    else
      thread = Repo.preload(thread, procedure_version: :procedure)

      Repo.transaction(fn ->
        {:ok, updated_thread} =
          thread
          |> ProcedureReviewThread.resolve_changeset(user_id)
          |> Repo.update()

        # Record the event
        record_version_event(
          thread.procedure_version,
          user_id,
          ProcedureThreadResolved,
          %{thread_id: thread.id}
        )

        updated_thread
      end)
    end
  end

  @doc """
  Reopens a resolved thread.
  """
  def reopen_thread(%ProcedureReviewThread{} = thread) do
    if thread.status == :open do
      {:error, :already_open}
    else
      thread
      |> ProcedureReviewThread.reopen_changeset()
      |> Repo.update()
    end
  end

  @doc """
  Creates a new discussion thread on a version.

  Unlike threads created from request_changes reviews, these are general
  discussion threads that are not blocking for resubmission.

  ## Options

  - `:anchor_type` - Where to anchor the thread: :version, :section, :step, or :block (default: :version)
  - `:anchor_id` - The UUID of the anchored element (required if anchor_type is not :version)
  - `:body` - Initial comment body (required)
  """
  def create_thread(%ProcedureVersion{} = version, user_id, opts \\ []) do
    body = Keyword.get(opts, :body)
    anchor_type = Keyword.get(opts, :anchor_type, :version)
    anchor_id = Keyword.get(opts, :anchor_id)

    if is_nil(body) or body == "" do
      {:error, :body_required}
    else
      version = Repo.preload(version, :procedure)

      Repo.transaction(fn ->
        {:ok, thread} =
          %ProcedureReviewThread{}
          |> ProcedureReviewThread.changeset(%{
            procedure_version_id: version.id,
            author_id: user_id,
            status: :open,
            anchor_type: anchor_type,
            anchor_id: anchor_id
          })
          |> Repo.insert()

        # Add the initial comment
        {:ok, _comment} =
          %ProcedureReviewComment{}
          |> ProcedureReviewComment.changeset(%{
            thread_id: thread.id,
            user_id: user_id,
            body: body
          })
          |> Repo.insert()

        # Record the event
        record_version_event(
          version,
          user_id,
          ProcedureReviewCommentAdded,
          %{thread_id: thread.id, body: body, anchor_type: anchor_type, anchor_id: anchor_id}
        )

        Repo.preload(thread, [:author, comments: :user])
      end)
    end
  end

  @doc """
  Lists threads for a specific anchor point.

  Returns all threads (open and resolved) anchored to the given element.
  """
  def list_threads_by_anchor(version_id, anchor_type, anchor_id \\ nil) do
    query =
      from t in ProcedureReviewThread,
        where:
          t.procedure_version_id == ^version_id and
            t.anchor_type == ^anchor_type,
        order_by: [asc: t.inserted_at],
        preload: [:author, :review, comments: :user]

    query =
      if anchor_id do
        where(query, [t], t.anchor_id == ^anchor_id)
      else
        where(query, [t], is_nil(t.anchor_id))
      end

    Repo.all(query)
  end

  @doc """
  Gets thread counts grouped by anchor for displaying badges in the review UI.

  Returns a map of anchor keys to thread counts:

      %{
        {:version, nil} => 2,
        {:section, "uuid1"} => 1,
        {:step, "uuid2"} => 3,
        {:block, "uuid3"} => 1
      }
  """
  def get_thread_counts_by_anchor(version_id) do
    query =
      from t in ProcedureReviewThread,
        where: t.procedure_version_id == ^version_id and t.status == :open,
        group_by: [t.anchor_type, t.anchor_id],
        select: {t.anchor_type, t.anchor_id, count(t.id)}

    Repo.all(query)
    |> Enum.into(%{}, fn {anchor_type, anchor_id, count} ->
      {{anchor_type, anchor_id}, count}
    end)
  end

  @doc """
  Gets the count of open threads anchored to a specific element.
  """
  def get_anchor_thread_count(version_id, anchor_type, anchor_id \\ nil) do
    query =
      from t in ProcedureReviewThread,
        where:
          t.procedure_version_id == ^version_id and
            t.anchor_type == ^anchor_type and
            t.status == :open,
        select: count(t.id)

    query =
      if anchor_id do
        where(query, [t], t.anchor_id == ^anchor_id)
      else
        where(query, [t], is_nil(t.anchor_id))
      end

    Repo.one(query)
  end

  # ============================================================================
  # Resubmit and Close Functions
  # ============================================================================

  @doc """
  Resubmits a version after addressing requested changes. (changes_requested → in_review)

  Validates that all blocking threads (from request_changes reviews) are resolved.
  Marks all existing reviews as superseded for a fresh review cycle.

  ## Options

  - `:note` - Optional note explaining what was changed
  """
  def resubmit(%ProcedureVersion{} = version, user_id, opts \\ []) do
    note = Keyword.get(opts, :note)

    with :ok <- validate_status(version, :changes_requested),
         :ok <- validate_can_resubmit(version, user_id),
         :ok <- validate_threads_resolved(version) do
      version = Repo.preload(version, :procedure)

      Repo.transaction(fn ->
        # Supersede all existing reviews
        from(r in ProcedureReview,
          where: r.procedure_version_id == ^version.id and r.superseded == false
        )
        |> Repo.update_all(set: [superseded: true])

        # Update version status
        updated =
          version
          |> ProcedureVersion.resubmit_changeset(%{
            submitted_at: DateTime.utc_now(),
            submitted_by_id: user_id
          })
          |> Repo.update!()

        # Record the resubmission
        record_version_event(updated, user_id, ProcedureVersionResubmitted, %{note: note})

        # Emit outbox event
        {:ok, _} =
          Outbox.insert(%{
            organization_id: version.procedure.organization_id,
            mission_id: version.procedure.mission_id,
            event_type: "procedure_resubmitted",
            aggregate_type: "procedure_version",
            aggregate_id: version.id,
            actor_id: user_id,
            actor_type: "user",
            payload: %{
              procedure_id: version.procedure_id,
              procedure_name: version.procedure.name,
              version_number: version.version_number,
              note: note
            }
          })

        updated
      end)
    end
  end

  @doc """
  Closes a version without approval. (any status → closed)

  Similar to closing a PR without merging. Can be done by the author or admins.

  ## Options

  - `:reason` - Optional reason for closing
  """
  def close_version(%ProcedureVersion{} = version, user_id, opts \\ []) do
    reason = Keyword.get(opts, :reason)

    if version.status in [:approved, :closed, :deprecated] do
      {:error, :cannot_close}
    else
      version = Repo.preload(version, :procedure)

      Repo.transaction(fn ->
        # Cancel any pending review requests
        from(rr in ProcedureReviewRequest,
          where: rr.procedure_version_id == ^version.id and rr.status == :pending
        )
        |> Repo.update_all(set: [status: :cancelled])

        # Update version status
        updated =
          version
          |> ProcedureVersion.close_changeset(%{})
          |> Repo.update!()

        # Record the closure
        record_version_event(updated, user_id, ProcedureVersionClosed, %{reason: reason})

        # Emit outbox event
        {:ok, _} =
          Outbox.insert(%{
            organization_id: version.procedure.organization_id,
            mission_id: version.procedure.mission_id,
            event_type: "procedure_version_closed",
            aggregate_type: "procedure_version",
            aggregate_id: version.id,
            actor_id: user_id,
            actor_type: "user",
            payload: %{
              procedure_id: version.procedure_id,
              procedure_name: version.procedure.name,
              version_number: version.version_number,
              reason: reason
            }
          })

        updated
      end)
    end
  end

  # ============================================================================
  # List Functions
  # ============================================================================

  @doc """
  Lists review threads for a version.

  ## Options

  - `:status` - Filter by status (:open or :resolved)
  - `:anchor_type` - Filter by anchor type (:version, :section, :step, :block)
  - `:anchor_id` - Filter by anchor ID (use nil for version-level threads)
  """
  def list_threads(version_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    anchor_type = Keyword.get(opts, :anchor_type)
    anchor_id = Keyword.get(opts, :anchor_id)

    query =
      from t in ProcedureReviewThread,
        where: t.procedure_version_id == ^version_id,
        order_by: [asc: t.inserted_at],
        preload: [:author, :review, comments: :user]

    query =
      if status do
        where(query, [t], t.status == ^status)
      else
        query
      end

    query =
      if anchor_type do
        query = where(query, [t], t.anchor_type == ^anchor_type)

        if anchor_id do
          where(query, [t], t.anchor_id == ^anchor_id)
        else
          where(query, [t], is_nil(t.anchor_id))
        end
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists comments in a thread.
  """
  def list_comments(thread_id) do
    from(c in ProcedureReviewComment,
      where: c.thread_id == ^thread_id,
      order_by: [asc: c.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Lists review requests for a version.

  ## Options

  - `:status` - Filter by status (:pending, :completed, :cancelled)
  """
  def list_review_requests(version_id, opts \\ []) do
    status = Keyword.get(opts, :status)

    query =
      from rr in ProcedureReviewRequest,
        where: rr.procedure_version_id == ^version_id,
        order_by: [asc: rr.inserted_at],
        preload: [:requester, :reviewer]

    query =
      if status do
        where(query, [rr], rr.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Requests a review from a specific user.

  Creates a pending review request. The requester is typically the author
  or someone on the team wanting additional reviews.

  Returns `{:ok, request}` or `{:error, changeset}`.

  ## Options

  - `:message` - Optional message to include with the request
  """
  def request_review(%ProcedureVersion{} = version, requester_id, reviewer_id, opts \\ []) do
    message = Keyword.get(opts, :message)

    attrs = %{
      procedure_version_id: version.id,
      requester_id: requester_id,
      reviewer_id: reviewer_id,
      message: message,
      status: :pending
    }

    # Check if there's already a pending request for this reviewer
    existing =
      from(rr in ProcedureReviewRequest,
        where:
          rr.procedure_version_id == ^version.id and
            rr.reviewer_id == ^reviewer_id and
            rr.status == :pending
      )
      |> Repo.one()

    if existing do
      {:error, :already_requested}
    else
      version = Repo.preload(version, :procedure)

      Multi.new()
      |> Multi.insert(
        :request,
        ProcedureReviewRequest.changeset(%ProcedureReviewRequest{}, attrs)
      )
      |> Recordings.append(
        :recorded,
        ProcedureReviewRequested,
        %{reviewer_id: reviewer_id, message: message},
        fn %{request: _request} ->
          version_recording_attrs(version.procedure, requester_id, version.id)
        end
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{request: request}} -> {:ok, Repo.preload(request, [:requester, :reviewer])}
        {:error, _step, changeset, _} -> {:error, changeset}
      end
    end
  end

  @doc """
  Gets a review thread by ID.
  """
  def get_thread(id), do: Repo.get(ProcedureReviewThread, id)
  def get_thread!(id), do: Repo.get!(ProcedureReviewThread, id)

  # ============================================================================
  # Private Review Workflow Helpers
  # ============================================================================

  defp validate_status(version, expected) do
    if version.status == expected, do: :ok, else: {:error, :invalid_status}
  end

  defp validate_status_in(version, statuses) do
    if version.status in statuses, do: :ok, else: {:error, :invalid_status}
  end

  defp validate_can_withdraw(version, user_id) do
    version = Repo.preload(version, procedure: :mission)

    if Settings.get(version.procedure.mission, :procedures, :allow_withdrawal) do
      if version.submitted_by_id == user_id or version.created_by_id == user_id do
        :ok
      else
        {:error, :not_author}
      end
    else
      {:error, :withdrawal_not_allowed}
    end
  end

  defp validate_can_review(version, user_id) do
    version = Repo.preload(version, procedure: :mission)
    allow_self = Settings.get(version.procedure.mission, :procedures, :allow_self_approval)

    if not allow_self and version.created_by_id == user_id do
      {:error, :cannot_review_own_work}
    else
      :ok
    end
  end

  defp validate_can_resubmit(version, user_id) do
    if version.submitted_by_id == user_id or version.created_by_id == user_id do
      :ok
    else
      {:error, :not_author}
    end
  end

  defp validate_threads_resolved(version) do
    open_blocking_threads =
      from(t in ProcedureReviewThread,
        where:
          t.procedure_version_id == ^version.id and
            t.status == :open and
            not is_nil(t.review_id)
      )
      |> Repo.aggregate(:count)

    if open_blocking_threads > 0 do
      {:error, :unresolved_threads}
    else
      :ok
    end
  end

  defp get_required_approvals(version) do
    version = Repo.preload(version, procedure: :mission)
    Settings.get(version.procedure.mission, :procedures, :required_approvals)
  end

  defp handle_review_decision(version, review, user_id, body) do
    case review.decision do
      :approve ->
        handle_approve_decision(version, user_id)

      :request_changes ->
        handle_request_changes_decision(version, review, user_id, body)
    end
  end

  defp handle_approve_decision(version, user_id) do
    # Check if approval threshold is met
    required = get_required_approvals(version)

    approved_count =
      from(r in ProcedureReview,
        where:
          r.procedure_version_id == ^version.id and
            r.decision == :approve and
            r.superseded == false
      )
      |> Repo.aggregate(:count)

    # Check for blocking reviews
    blocking_count =
      from(r in ProcedureReview,
        where:
          r.procedure_version_id == ^version.id and
            r.decision == :request_changes and
            r.superseded == false
      )
      |> Repo.aggregate(:count)

    if approved_count >= required and blocking_count == 0 do
      updated =
        version
        |> ProcedureVersion.approval_changeset(%{
          status: :approved,
          approved_at: DateTime.utc_now(),
          approved_by_id: user_id
        })
        |> Repo.update!()

      # Update procedure's current version pointer
      from(p in Procedure, where: p.id == ^version.procedure_id)
      |> Repo.update_all(set: [current_version_id: version.id])

      # Emit outbox event for finalization
      {:ok, _} =
        Outbox.insert(%{
          organization_id: version.procedure.organization_id,
          mission_id: version.procedure.mission_id,
          event_type: "procedure_finalized",
          aggregate_type: "procedure_version",
          aggregate_id: version.id,
          actor_id: user_id,
          actor_type: "user",
          payload: %{
            procedure_id: version.procedure_id,
            procedure_name: version.procedure.name,
            version_number: version.version_number
          }
        })

      {updated, nil}
    else
      {version, nil}
    end
  end

  defp handle_request_changes_decision(version, review, user_id, body) do
    # Create a review thread for the change request
    {:ok, thread} =
      %ProcedureReviewThread{}
      |> ProcedureReviewThread.changeset(%{
        procedure_version_id: version.id,
        author_id: user_id,
        review_id: review.id,
        status: :open
      })
      |> Repo.insert()

    # Add the review body as the first comment in the thread
    {:ok, _comment} =
      %ProcedureReviewComment{}
      |> ProcedureReviewComment.changeset(%{
        thread_id: thread.id,
        user_id: user_id,
        body: body
      })
      |> Repo.insert()

    # Transition version to changes_requested if not already
    updated =
      if version.status != :changes_requested do
        version
        |> ProcedureVersion.changes_requested_changeset(%{})
        |> Repo.update!()
      else
        version
      end

    {updated, thread}
  end

  defp record_review_event(version, _updated_version, user_id, :approve, body, _thread) do
    record_version_event(version, user_id, ProcedureReviewApproved, %{body: body})
  end

  defp record_review_event(version, _updated_version, user_id, :request_changes, body, thread) do
    record_version_event(version, user_id, ProcedureChangesRequested, %{
      body: body,
      thread_id: thread && thread.id
    })
  end

  defp record_version_event(
         %ProcedureVersion{} = version,
         user_id,
         recordable_module,
         recordable_attrs
       ) do
    version = Repo.preload(version, :procedure)

    # Look up the mission's bucket (procedures are scoped to missions)
    bucket_id = get_mission_bucket_id(version.procedure.mission_id)

    recording_attrs = %{
      organization_id: version.procedure.organization_id,
      bucket_id: bucket_id,
      aggregate_type: "ProcedureVersion",
      aggregate_id: version.id,
      actor_id: user_id,
      actor_type: if(user_id, do: "user", else: "system"),
      timestamp: DateTime.utc_now()
    }

    case Recordings.create(recordable_module, recordable_attrs, recording_attrs) do
      {:ok, _} -> :ok
      # Don't fail for recording errors
      {:error, _, _, _} -> :ok
    end
  end

  defp get_mission_bucket_id(nil), do: nil

  defp get_mission_bucket_id(mission_id) do
    case Cadence.Buckets.get_bucket_by_bucketable("Mission", mission_id) do
      nil -> nil
      bucket -> bucket.id
    end
  end

  # ============================================================================
  # Executions
  # ============================================================================

  @doc """
  Lists executions, optionally filtered.
  """
  def list_executions(opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    ProcedureExecution
    |> maybe_filter(:organization_id, organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:procedure_id, procedure_id)
    |> maybe_filter(:status, status)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  @doc """
  Gets an execution by ID.
  """
  def get_execution(id), do: Repo.get(ProcedureExecution, id)

  @doc """
  Gets an execution by ID with preloads.
  """
  def get_execution!(id) do
    ProcedureExecution
    |> Repo.get!(id)
    |> Repo.preload([:procedure, :procedure_version])
  end

  @doc """
  Starts a new procedure execution.

  Starts a V2 ExecutionProcess, which creates the execution record.

  Parameters are validated against the procedure version's `parameters_schema`
  before execution begins. If validation fails, returns `{:error, {:validation, errors}}`.

  ## Options

  - `:version_id` - Specific version to run (defaults to current version)
  - `:target_id` - Target for the execution
  - `:parameters` - Runtime parameters (validated against schema)
  - `:user_id` - User triggering the execution
  - `:triggered_by` - Trigger source (`:manual`, `:schedule`, `:event`)
  - `:trigger_context` - Context data from trigger (for event-driven executions)
  - `:skip_validation` - Skip parameter validation (use with caution)
  """
  def start_execution(procedure_id, opts \\ []) do
    version_id = Keyword.get(opts, :version_id)
    target_id = Keyword.get(opts, :target_id)
    parameters = Keyword.get(opts, :parameters, %{})
    user_id = Keyword.get(opts, :user_id)
    triggered_by = Keyword.get(opts, :triggered_by, :manual)
    trigger_context = Keyword.get(opts, :trigger_context)
    skip_validation = Keyword.get(opts, :skip_validation, false)

    procedure = get_procedure!(procedure_id)

    # Use specified version or current version
    version =
      if version_id do
        get_version!(version_id)
      else
        if procedure.current_version_id do
          get_version!(procedure.current_version_id)
        else
          raise "No version available for procedure #{procedure_id}"
        end
      end

    # Validate parameters against schema
    validation_context = %{
      mission_id: procedure.mission_id,
      organization_id: procedure.organization_id
    }

    with {:ok, validated_params} <-
           maybe_validate_params(parameters, version, validation_context, skip_validation),
         {:ok, resolved_target_id} <- resolve_target_id(target_id, procedure.mission_id),
         {:ok, pid} <-
           start_execution_process(
             version,
             validated_params,
             target_id: resolved_target_id,
             user_id: user_id,
             triggered_by: triggered_by,
             trigger_context: trigger_context
           ) do
      {:ok, Cadence.Procedures.V2.ExecutionProcess.get_execution(pid)}
    end
  end

  defp maybe_validate_params(params, _version, _context, true), do: {:ok, params}

  defp maybe_validate_params(params, version, context, false) do
    case Parameters.validate(params, version.parameters_schema, context) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, {:validation, errors}}
    end
  end

  defp resolve_target_id(nil, _mission_id), do: {:ok, nil}

  defp resolve_target_id(target_id, mission_id) when is_binary(target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        {:ok, uuid}

      :error ->
        case Targets.get_target_by_identifier(mission_id, target_id) do
          {:ok, target} -> {:ok, target.id}
          {:error, :not_found} -> {:error, {:target_not_found, target_id}}
        end
    end
  end

  defp start_execution_process(version, params, opts) do
    DynamicSupervisor.start_child(
      Cadence.Procedures.ExecutionSupervisor,
      {Cadence.Procedures.V2.ExecutionProcess,
       [
         procedure_version: version,
         params: params,
         target_id: opts[:target_id],
         user_id: opts[:user_id],
         triggered_by: opts[:triggered_by],
         trigger_context: opts[:trigger_context]
       ]}
    )
  end

  # ============================================================================
  # Import/Export
  # ============================================================================

  @doc """
  Exports a procedure to a portable JSON-compatible map.

  Exports the current approved version (or latest draft if none approved).
  Does not include version history or execution records.
  """
  def export_procedure(%Procedure{} = procedure) do
    procedure = Repo.preload(procedure, :current_version)

    version_data =
      if procedure.current_version do
        %{
          "version_number" => procedure.current_version.version_number,
          "source" => procedure.current_version.source,
          "parameters_schema" => procedure.current_version.parameters_schema,
          "change_summary" => procedure.current_version.change_summary,
          "allow_hazardous_commands" => procedure.current_version.allow_hazardous_commands
        }
      else
        nil
      end

    %{
      "export_version" => "1.0.0",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source_procedure_id" => procedure.id,
      "source_mission_id" => procedure.mission_id,
      "procedure" => %{
        "name" => procedure.name,
        "description" => procedure.description,
        "type" => to_string(procedure.type),
        "tags" => procedure.tags || [],
        "version" => version_data
      }
    }
  end

  @doc """
  Imports a procedure from an export map into a target mission.

  Creates a new procedure with version 1 in draft status.
  The imported procedure requires approval before use.

  ## Options
  - `:user_id` - User performing the import (required, for audit)
  - `:name` - Override the procedure name (optional)

  ## Returns
  `{:ok, procedure}` or `{:error, reason}`

  ## Error Reasons
  - `:invalid_export_format` - Export data doesn't match expected schema
  - `:name_already_exists` - A procedure with this name already exists
  - `:missing_version_data` - Export has no version data to import
  """
  def import_procedure(organization_id, mission_id, export_data, opts \\ []) do
    user_id = Keyword.fetch!(opts, :user_id)
    name_override = Keyword.get(opts, :name)

    with {:ok, validated} <- validate_export_format(export_data),
         {:ok, name} <-
           resolve_import_name(organization_id, mission_id, validated, name_override),
         {:ok, version_data} <- extract_version_data(validated) do
      procedure_attrs = %{
        name: name,
        description: validated["procedure"]["description"],
        type: String.to_existing_atom(validated["procedure"]["type"]),
        tags: validated["procedure"]["tags"] || [],
        organization_id: organization_id,
        mission_id: mission_id
      }

      create_procedure(
        procedure_attrs,
        user_id: user_id,
        source: version_data["source"] || %{"steps" => %{}},
        parameters_schema: version_data["parameters_schema"] || %{},
        allow_hazardous_commands: version_data["allow_hazardous_commands"] || false
      )
    end
  end

  defp validate_export_format(%{"export_version" => "1.0.0", "procedure" => proc} = data)
       when is_map(proc) do
    case {proc["name"], proc["type"]} do
      {name, type} when is_binary(name) and is_binary(type) -> {:ok, data}
      _ -> {:error, :invalid_export_format}
    end
  end

  defp validate_export_format(_), do: {:error, :invalid_export_format}

  defp resolve_import_name(org_id, mission_id, validated, nil) do
    name = validated["procedure"]["name"]

    case get_procedure_by_name(org_id, mission_id, name) do
      nil -> {:ok, name}
      _ -> {:error, :name_already_exists}
    end
  end

  defp resolve_import_name(org_id, mission_id, _validated, name_override) do
    case get_procedure_by_name(org_id, mission_id, name_override) do
      nil -> {:ok, name_override}
      _ -> {:error, :name_already_exists}
    end
  end

  defp extract_version_data(%{"procedure" => %{"version" => nil}}),
    do: {:error, :missing_version_data}

  defp extract_version_data(%{"procedure" => %{"version" => v}}) when is_map(v),
    do: {:ok, v}

  defp extract_version_data(_),
    do: {:error, :missing_version_data}
end
