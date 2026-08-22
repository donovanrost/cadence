defmodule CadenceWeb.API.CommandingParams do
  @moduledoc "Commanding request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.Commanding.{CommandRequest, CommandStage, StagedCommandItem}

  @command_stage_visibility_values [:private, :shared]
  @command_stage_lifecycle_states [:draft, :in_review, :ready_to_submit, :submitted, :canceled]
  @staged_command_item_lifecycle_states [:draft, :submitted, :canceled]
  @command_request_lifecycle_states [
    :draft,
    :validated,
    :approval_pending,
    :approved,
    :rejected,
    :queued,
    :released,
    :canceled
  ]
  @command_approval_decisions [:approved, :rejected]
  @command_queue_entry_lifecycle_states [:pending, :release_pending, :released, :canceled]
  @command_release_attempt_lifecycle_states [
    :release_pending,
    :released,
    :release_failed,
    :canceled
  ]
  @command_verifier_instance_lifecycle_states [
    :pending,
    :satisfied,
    :failed,
    :timed_out,
    :canceled
  ]
  @command_verifier_phases [:acceptance, :start, :completion, :custom]
  @spec command_stage(binary(), binary(), map(), keyword()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def command_stage(organization_id, mission_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) and
             is_list(opts) do
    with {:ok, stage_name} <- required_string(params, "stage_name"),
         {:ok, visibility} <- command_stage_visibility(params, :private),
         {:ok, lifecycle_state} <- command_stage_lifecycle_state(params, :draft),
         {:ok, owner} <- optional_map(params, "owner", Keyword.get(opts, :default_owner, %{})) do
      {:ok,
       CommandStage.new(%{
         command_stage_id: string_value(params, "command_stage_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         stage_name: stage_name,
         description: string_value(params, "description"),
         owner: owner || %{},
         visibility: visibility,
         lifecycle_state: lifecycle_state,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec command_stage(CommandStage.t(), map()) :: {:ok, CommandStage.t()} | {:error, term()}
  def command_stage(%CommandStage{} = existing_command_stage, params) when is_map(params) do
    with {:ok, visibility} <-
           command_stage_visibility(params, existing_command_stage.visibility),
         {:ok, lifecycle_state} <-
           command_stage_lifecycle_state(params, existing_command_stage.lifecycle_state),
         {:ok, owner} <- maybe_map_override(params, "owner", existing_command_stage.owner) do
      {:ok,
       CommandStage.new(%{
         command_stage_id: existing_command_stage.command_stage_id,
         organization_id: existing_command_stage.organization_id,
         mission_id: existing_command_stage.mission_id,
         stage_name:
           maybe_string_override(params, "stage_name", existing_command_stage.stage_name),
         description:
           maybe_nullable_string_override(
             params,
             "description",
             existing_command_stage.description
           ),
         owner: owner,
         visibility: visibility,
         lifecycle_state: lifecycle_state,
         metadata: maybe_map_value(params, "metadata", existing_command_stage.metadata)
       })}
    end
  end

  @spec command_stage_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_stage_filters(params) when is_map(params) do
    with {:ok, visibility} <- optional_command_stage_visibility(params),
         {:ok, lifecycle_state} <- optional_command_stage_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:visibility, visibility)
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec staged_command_item(binary(), binary(), binary(), map()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def staged_command_item(organization_id, mission_id, command_stage_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_stage_id) and is_map(params) do
    with {:ok, scoped_command_stage_id} <-
           resolve_scoped_command_stage_id(params, command_stage_id),
         {:ok, source_endpoint_ref} <- required_string(params, "source_endpoint_ref"),
         {:ok, mission_model_revision_id} <- required_string(params, "mission_model_revision_id"),
         {:ok, command_id} <- required_string(params, "command_id"),
         {:ok, priority} <- non_neg_integer(params, "priority", 3),
         {:ok, item_order} <- non_neg_integer(params, "item_order", 0),
         {:ok, not_before} <- optional_datetime(params, "not_before"),
         {:ok, expires_at} <- optional_datetime(params, "expires_at") do
      {:ok,
       StagedCommandItem.new(%{
         staged_command_item_id: string_value(params, "staged_command_item_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         command_stage_id: scoped_command_stage_id,
         source_endpoint_ref: source_endpoint_ref,
         mission_model_revision_id: mission_model_revision_id,
         command_id: command_id,
         argument_values: map_value(params, "argument_values"),
         priority: priority,
         not_before: not_before,
         expires_at: expires_at,
         notes: string_value(params, "notes"),
         item_order: item_order,
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec staged_command_item(StagedCommandItem.t(), map()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def staged_command_item(%StagedCommandItem{} = existing_staged_command_item, params)
      when is_map(params) do
    with {:ok, priority} <-
           maybe_non_neg_integer(params, "priority", existing_staged_command_item.priority),
         {:ok, item_order} <-
           maybe_non_neg_integer(params, "item_order", existing_staged_command_item.item_order),
         {:ok, not_before} <-
           maybe_optional_datetime(params, "not_before", existing_staged_command_item.not_before),
         {:ok, expires_at} <-
           maybe_optional_datetime(params, "expires_at", existing_staged_command_item.expires_at) do
      {:ok,
       StagedCommandItem.new(%{
         staged_command_item_id: existing_staged_command_item.staged_command_item_id,
         organization_id: existing_staged_command_item.organization_id,
         mission_id: existing_staged_command_item.mission_id,
         command_stage_id: existing_staged_command_item.command_stage_id,
         source_endpoint_ref:
           maybe_string_override(
             params,
             "source_endpoint_ref",
             existing_staged_command_item.source_endpoint_ref
           ),
         mission_model_revision_id:
           maybe_string_override(
             params,
             "mission_model_revision_id",
             existing_staged_command_item.mission_model_revision_id
           ),
         command_id:
           maybe_string_override(params, "command_id", existing_staged_command_item.command_id),
         argument_values:
           maybe_map_value(
             params,
             "argument_values",
             existing_staged_command_item.argument_values
           ),
         priority: priority,
         not_before: not_before,
         expires_at: expires_at,
         notes:
           maybe_nullable_string_override(params, "notes", existing_staged_command_item.notes),
         item_order: item_order,
         lifecycle_state: existing_staged_command_item.lifecycle_state,
         submitted_command_request_id: existing_staged_command_item.submitted_command_request_id,
         metadata: maybe_map_value(params, "metadata", existing_staged_command_item.metadata)
       })}
    end
  end

  @spec staged_command_item_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def staged_command_item_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_staged_command_item_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_stage_id, string_value(params, "command_stage_id"))
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_stage_submission(map(), keyword()) ::
          {:ok, {[binary()], map()}} | {:error, term()}
  def command_stage_submission(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, staged_command_item_ids} <- required_string_list(params, "staged_command_item_ids"),
         {:ok, requested_by} <-
           optional_map(params, "requested_by", Keyword.get(opts, :default_requested_by, %{})) do
      {:ok, {staged_command_item_ids, requested_by || %{}}}
    end
  end

  @spec command_request(binary(), binary(), map(), keyword()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def command_request(organization_id, mission_id, params, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) and
             is_list(opts) do
    with {:ok, source_endpoint_ref} <- required_string(params, "source_endpoint_ref"),
         {:ok, mission_model_revision_id} <- required_string(params, "mission_model_revision_id"),
         {:ok, command_id} <- required_string(params, "command_id"),
         {:ok, priority} <- non_neg_integer(params, "priority", 3),
         {:ok, not_before} <- optional_datetime(params, "not_before"),
         {:ok, expires_at} <- optional_datetime(params, "expires_at"),
         {:ok, requested_by} <-
           optional_map(params, "requested_by", Keyword.get(opts, :default_requested_by, %{})) do
      {:ok,
       CommandRequest.new(%{
         command_request_id: string_value(params, "command_request_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         source_endpoint_ref: source_endpoint_ref,
         mission_model_revision_id: mission_model_revision_id,
         command_id: command_id,
         priority: priority,
         not_before: not_before,
         expires_at: expires_at,
         requested_by: requested_by || %{},
         argument_values: map_value(params, "argument_values"),
         metadata: map_value(params, "metadata")
       })}
    end
  end

  @spec command_request_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_request_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_request_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:command_stage_id, string_value(params, "command_stage_id"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_approval(binary(), map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def command_approval(command_request_id, params, opts \\ [])
      when is_binary(command_request_id) and is_map(params) and is_list(opts) do
    with {:ok, decided_by} <-
           optional_map(params, "decided_by", Keyword.get(opts, :default_decided_by, %{})) do
      {:ok,
       [
         reason: string_value(params, "reason"),
         decided_by: decided_by || %{},
         metadata: map_value(params, "metadata")
       ]}
    end
  end

  @spec command_approval_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_approval_filters(params) when is_map(params) do
    with {:ok, decision} <- optional_command_approval_decision(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_request_id, string_value(params, "command_request_id"))
       |> maybe_put_opt(:decision, decision)}
    end
  end

  @spec command_queue_entry(map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def command_queue_entry(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, enqueued_by} <-
           optional_map(params, "enqueued_by", Keyword.get(opts, :default_enqueued_by, %{})) do
      {:ok,
       [
         enqueued_by: enqueued_by || %{},
         metadata: map_value(params, "metadata")
       ]}
    end
  end

  @spec command_queue_entry_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_queue_entry_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_queue_entry_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:queue_lane_key, string_value(params, "queue_lane_key"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_release_attempt(map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def command_release_attempt(params, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, realized_contact_id} <- required_string(params, "realized_contact_id"),
         {:ok, released_by} <-
           optional_map(params, "released_by", Keyword.get(opts, :default_released_by, %{})),
         {:ok, attempted_at} <- optional_datetime(params, "attempted_at") do
      {:ok,
       []
       |> Keyword.put(:realized_contact_id, realized_contact_id)
       |> Keyword.put(:released_by, released_by || %{})
       |> maybe_put_opt(:path_id, string_value(params, "path_id"))
       |> maybe_put_opt(:transport_binding_id, string_value(params, "transport_binding_id"))
       |> maybe_put_opt(:attempted_at, attempted_at)
       |> Keyword.put(:metadata, map_value(params, "metadata"))}
    end
  end

  @spec command_release_attempt_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_release_attempt_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_release_attempt_lifecycle_state(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_request_id, string_value(params, "command_request_id"))
       |> maybe_put_opt(:command_queue_entry_id, string_value(params, "command_queue_entry_id"))
       |> maybe_put_opt(:realized_contact_id, string_value(params, "realized_contact_id"))
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  @spec command_verifier_instance_filters(map()) :: {:ok, keyword()} | {:error, term()}
  def command_verifier_instance_filters(params) when is_map(params) do
    with {:ok, lifecycle_state} <- optional_command_verifier_instance_lifecycle_state(params),
         {:ok, phase} <- optional_command_verifier_phase(params) do
      {:ok,
       []
       |> maybe_put_opt(:command_request_id, string_value(params, "command_request_id"))
       |> maybe_put_opt(
         :command_release_attempt_id,
         string_value(params, "command_release_attempt_id")
       )
       |> maybe_put_opt(:source_endpoint_ref, string_value(params, "source_endpoint_ref"))
       |> maybe_put_opt(:phase, phase)
       |> maybe_put_opt(:lifecycle_state, lifecycle_state)}
    end
  end

  defp command_stage_visibility(params, default) when is_map(params) do
    allowed_atom_param(params, "visibility", default, @command_stage_visibility_values)
  end

  defp optional_command_stage_visibility(params) when is_map(params) do
    optional_allowed_atom_param(params, "visibility", @command_stage_visibility_values)
  end

  defp command_stage_lifecycle_state(params, default) when is_map(params) do
    allowed_atom_param(params, "lifecycle_state", default, @command_stage_lifecycle_states)
  end

  defp optional_command_stage_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @command_stage_lifecycle_states)
  end

  defp optional_staged_command_item_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @staged_command_item_lifecycle_states)
  end

  defp optional_command_request_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @command_request_lifecycle_states)
  end

  defp optional_command_approval_decision(params) when is_map(params) do
    optional_allowed_atom_param(params, "decision", @command_approval_decisions)
  end

  defp optional_command_queue_entry_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(params, "lifecycle_state", @command_queue_entry_lifecycle_states)
  end

  defp optional_command_release_attempt_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(
      params,
      "lifecycle_state",
      @command_release_attempt_lifecycle_states
    )
  end

  defp optional_command_verifier_instance_lifecycle_state(params) when is_map(params) do
    optional_allowed_atom_param(
      params,
      "lifecycle_state",
      @command_verifier_instance_lifecycle_states
    )
  end

  defp optional_command_verifier_phase(params) when is_map(params) do
    optional_allowed_atom_param(params, "phase", @command_verifier_phases)
  end
end
