defmodule Cadence.Management.Commanding.StageItemAuthoring do
  @moduledoc "Validated command intent for new or edited stage drafts, with server-owned identities."
  import Ecto.Query

  alias Cadence.Commanding.{
    LifecyclePolicy,
    RequestValidation,
    StagedCommandItem,
    StagedCommandItemRow
  }

  alias Cadence.Ids
  alias Cadence.Management.Commanding.{RequestAuthoring, StageAccess, StageCatalog, StageInput}
  alias Cadence.Repo

  def preview(
        scope,
        mission_id,
        stage_id,
        item_id,
        %{"expected_stage" => stage_token, "expected_item" => item_token, "command" => command} =
          input
      )
      when map_size(input) == 3 do
    StageAccess.with_stage(scope, mission_id, stage_id, :write, fn fresh, _, stage ->
      with :ok <- expected(stage_token, StageCatalog.stage_token(stage)),
           :ok <- LifecyclePolicy.ensure_stage_editable(stage),
           :ok <- observed_item(stage, item_id, item_token),
           {:ok, authoring} <- RequestAuthoring.preview(scope, mission_id, command),
           {:ok, _, _} <- StageAccess.authorize(scope, mission_id) do
        held = %{
          organization_id: fresh.organization_id,
          mission_id: mission_id,
          stage_id: stage_id,
          actor_id: fresh.user.user_id,
          expected_stage: stage_token,
          expected_item: item_token,
          item_id: item_id || Ids.new("staged_command_item"),
          new?: is_nil(item_id),
          authoring: authoring
        }

        {:ok, Map.put(held, :token, RequestValidation.authoring_digest(held))}
      end
    end)
  end

  def preview(_, _, _, _, _), do: {:error, :invalid_command_stage_input}

  def save(scope, mission_id, stage_id, write_token, held, input) do
    with {:ok, input} <- parse_save(held, input),
         :ok <- expected(input.expected_write, write_token),
         :ok <- expected(input.expected_preview, held.token) do
      StageAccess.with_stage(
        scope,
        mission_id,
        stage_id,
        :write,
        fn fresh, _, stage ->
          save_locked(scope, fresh, stage, held, input)
        end,
        notify: true
      )
    end
  end

  def public_preview(held),
    do: %{
      "token" => held.token,
      "item_id" => held.item_id,
      "stage_id" => held.stage_id,
      "new" => held.new?,
      "command" =>
        held.authoring
        |> RequestAuthoring.public_preview()
        |> Map.drop(~w(token request_id lifecycle_state requested_at))
    }

  defp save_locked(scope, fresh, stage, held, input) do
    with :ok <- held_identity(fresh, stage, held),
         :ok <- expected(input.expected_stage, held.expected_stage),
         :ok <- expected(held.expected_stage, StageCatalog.stage_token(stage)),
         :ok <- LifecyclePolicy.ensure_stage_editable(stage),
         :ok <-
           observed_item(stage, if(held.new?, do: nil, else: held.item_id), held.expected_item) do
      RequestValidation.with_authoring_request(
        held.authoring.request,
        held.authoring.expected_basis,
        held.authoring.expected_target,
        fn request, _ -> persist_validated(scope, stage, held, input, request) end
      )
    end
  end

  defp persist_validated(scope, stage, held, input, request) do
    with true <- request == held.authoring.request,
         {:ok, fresh, _} <- StageAccess.authorize(scope, stage.mission_id),
         :ok <- LifecyclePolicy.ensure_request_not_expired(request) do
      persist_item(stage, fresh, held, input, request)
    else
      false -> {:error, :command_stage_changed}
      error -> error
    end
  end

  defp persist_item(stage, fresh, held, input, request) do
    with {:ok, original} <- original_item(stage, held) do
      item = %{
        original
        | source_endpoint_ref: request.source_endpoint_ref,
          mission_model_revision_id: request.mission_model_revision_id,
          command_id: request.command_id,
          argument_values: request.argument_values,
          priority: request.priority,
          not_before: request.not_before,
          expires_at: request.expires_at,
          notes: input.notes,
          item_order: input.order
      }

      result =
        if held.new?,
          do: Repo.insert(StagedCommandItemRow.changeset(item)),
          else: update_item(stage, item)

      with {:ok, row} <- result do
        {:ok,
         %{
           "operation" => if(held.new?, do: "item_created", else: "item_updated"),
           "stage_id" => stage.command_stage_id,
           "item_id" => row.staged_command_item_id,
           "actor_id" => fresh.user.user_id,
           "updated_at" => DateTime.to_iso8601(row.updated_at)
         }}
      end
    end
  end

  defp original_item(stage, %{new?: true, item_id: id}) do
    {:ok,
     StagedCommandItem.new(%{
       staged_command_item_id: id,
       organization_id: stage.organization_id,
       mission_id: stage.mission_id,
       command_stage_id: stage.command_stage_id,
       source_endpoint_ref: nil,
       mission_model_revision_id: nil,
       command_id: nil
     })}
  end

  defp original_item(stage, held) do
    case item_row(stage, held.item_id) do
      nil -> {:error, :unavailable}
      row -> {:ok, StagedCommandItemRow.to_domain(row)}
    end
  end

  defp update_item(stage, item) do
    case item_row(stage, item.staged_command_item_id) do
      nil -> {:error, :unavailable}
      row -> Repo.update(StagedCommandItemRow.update_changeset(row, item))
    end
  end

  defp item_row(stage, item_id) do
    Repo.one(
      from(row in StagedCommandItemRow,
        where:
          row.organization_id == ^stage.organization_id and row.mission_id == ^stage.mission_id and
            row.command_stage_id == ^stage.command_stage_id and
            row.staged_command_item_id == ^item_id,
        where:
          fragment("octet_length(?::text)", row.argument_values_document) <= 32_768 and
            fragment("octet_length(?::text)", row.metadata_document) <= 65_536,
        where: is_nil(row.notes) or fragment("octet_length(?)", row.notes) <= 4_000,
        lock: "FOR UPDATE"
      )
    )
  end

  defp observed_item(_, nil, nil), do: :ok

  defp observed_item(stage, id, token) when is_binary(id) and is_binary(token) do
    case stage
         |> StageCatalog.item_query()
         |> where([row], row.staged_command_item_id == ^id)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      %{
        token: ^token,
        lifecycle_state: "draft",
        notes_available: true,
        argument_values_document: args
      }
      when is_map(args) ->
        :ok

      _ ->
        {:error, :command_stage_changed}
    end
  end

  defp observed_item(_, _, _), do: {:error, :command_stage_changed}

  defp parse_save(%{new?: true}, input), do: StageInput.add_item(input)

  defp parse_save(held, input) do
    with {:ok, parsed} <- StageInput.edit_item(input),
         :ok <- expected(parsed.expected_item, held.expected_item),
         do: {:ok, parsed}
  end

  defp held_identity(fresh, stage, held) do
    if held.organization_id == fresh.organization_id and held.mission_id == stage.mission_id and
         held.stage_id == stage.command_stage_id and held.actor_id == fresh.user.user_id and
         held.token == RequestValidation.authoring_digest(Map.delete(held, :token)),
       do: :ok,
       else: {:error, :command_stage_changed}
  end

  defp expected(value, value) when is_binary(value), do: :ok
  defp expected(_, _), do: {:error, :command_stage_changed}
end
