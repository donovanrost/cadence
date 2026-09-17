defmodule CadenceWeb.OpsCommandWorkspaceWrites do
  @moduledoc false
  alias Cadence.Control.Commanding.WorkspaceSubmission

  alias Cadence.Management.Commanding.{
    StageCatalog,
    StageDrafts,
    StageSubmission,
    WorkspaceDrafts
  }

  alias CadenceWeb.OpsCommandWorkspaceSession, as: Session
  @events ~w(create_stage save_targets enqueue submit cancel_item edit_details)

  def action(scope, session, event, %{"expected_write" => token} = input) when event in @events do
    if Session.available?(session) and token == session.write_token do
      stage_id = operation_stage(session, event)
      operation = %{status: "unconfirmed", event: event, stage_id: stage_id, write_token: token}
      session = %{session | operation: operation}
      session = if event == "create_stage", do: %{session | create_input: input}, else: session
      result = perform(scope, session, event, input)
      result = Map.merge(operation, result)
      session = %{session | operation: result} |> after_write()
      {result, session}
    else
      {Session.rejected("This action was already attempted. Refresh to inspect its result."),
       session}
    end
  end

  def action(_, session, _, _), do: {Session.rejected("Invalid workspace action."), session}

  def recover(scope, %{operation: %{status: "unconfirmed"} = operation} = session) do
    {_, _, mission, _} = session.identity

    result =
      case operation.event do
        "enqueue" when is_map(session.queue_preview) ->
          WorkspaceSubmission.recover(scope, mission, session.queue_preview)

        "save_targets" when is_map(session.draft_preview) ->
          WorkspaceDrafts.recover(scope, mission, session.draft_preview)

        "submit" when is_map(session.batch_preview) ->
          StageSubmission.recover(scope, mission, session.stage_id, session.batch_preview)

        "create_stage" ->
          recover_creation(scope, mission, session)

        _ ->
          {:error, :unconfirmed}
      end

    case result do
      {:ok, receipt} ->
        %{session | operation: Map.merge(operation, %{status: "completed", receipt: receipt})}
        |> after_write()

      _ ->
        session
    end
  rescue
    _ -> session
  end

  def recover(_, session), do: session

  defp perform(scope, session, event, input) do
    case write(scope, session, event, input) do
      {:ok, receipt} ->
        %{status: "completed", receipt: receipt}

      {:error, :command_stage_changed} ->
        Session.rejected(
          "The stage or a selected draft changed. Refresh and review the current contents."
        )

      {:error, :command_authoring_basis_changed} ->
        Session.rejected(
          "The command model or an endpoint changed. Refresh and prepare new previews."
        )

      {:error, :command_authoring_preview_changed} ->
        Session.rejected(
          "The command preview changed. Preview the endpoints again before enqueueing."
        )

      {:error, _} ->
        Session.rejected("The change was not saved. Check your access and inputs, then refresh.")
    end
  rescue
    _ -> %{status: "unconfirmed"}
  catch
    _, _ -> %{status: "unconfirmed"}
  end

  defp write(scope, session, event, input) do
    {_, _, mission, _} = session.identity

    case event do
      "enqueue" ->
        WorkspaceSubmission.submit(
          scope,
          mission,
          session.write_token,
          session.queue_preview,
          input
        )

      "create_stage" ->
        StageDrafts.create(
          scope,
          mission,
          %{session.creation | write_token: session.write_token},
          input
        )

      "save_targets" ->
        WorkspaceDrafts.save(
          scope,
          mission,
          session.stage_id,
          session.write_token,
          session.draft_preview,
          input
        )

      "submit" when is_map(session.batch_preview) ->
        StageSubmission.submit(
          scope,
          mission,
          session.stage_id,
          session.write_token,
          session.batch_preview,
          input
        )

      event when event in ["cancel_item", "edit_details"] ->
        maintain(scope, mission, session, event, input)

      _ ->
        {:error, :invalid_command_stage_input}
    end
  end

  defp maintain(scope, mission, session, event, input) do
    item_id = input["item_id"]

    if Session.visible_items?(session, [
         %{"id" => item_id, "expected_item" => input["expected_item"]}
       ]) do
      fields = Map.delete(input, "item_id")

      case event do
        "cancel_item" ->
          StageDrafts.cancel_item(
            scope,
            mission,
            session.stage_id,
            item_id,
            session.write_token,
            fields
          )

        "edit_details" ->
          StageDrafts.edit_details(
            scope,
            mission,
            session.stage_id,
            item_id,
            session.write_token,
            fields
          )
      end
    else
      {:error, :command_stage_changed}
    end
  end

  defp after_write(
         %{operation: %{status: "completed", event: "create_stage", receipt: receipt}} = session
       ),
       do: %{
         session
         | stage_id: receipt["stage_id"],
           stage_query: %{},
           creation: nil,
           draft_preview: nil,
           queue_preview: nil,
           batch_preview: nil
       }

  defp after_write(%{operation: %{status: "completed"}} = session),
    do: %{session | draft_preview: nil, queue_preview: nil, batch_preview: nil}

  defp after_write(session), do: session

  defp operation_stage(_session, "enqueue"), do: nil
  defp operation_stage(session, "create_stage"), do: session.creation.stage_id
  defp operation_stage(session, _event), do: session.stage_id

  defp recover_creation(scope, mission, session) do
    input = session.create_input

    with {:ok, model} <- StageCatalog.workbench(scope, mission, session.creation.stage_id, %{}),
         stage = model["stage"],
         true <-
           stage["owner_id"] == session.creation.actor_id and
             stage["name"] == String.trim(input["name"]) and
             stage["description"] == input["description"] and
             stage["visibility"] == input["visibility"] do
      {:ok,
       %{
         "operation" => "stage_created",
         "stage_id" => stage["id"],
         "actor_id" => session.creation.actor_id,
         "name" => stage["name"],
         "state" => stage["state"],
         "visibility" => stage["visibility"]
       }}
    else
      _ -> {:error, :unconfirmed}
    end
  end
end
