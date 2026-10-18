defmodule CadenceWeb.OpsCommandStagesActions do
  @moduledoc "Finite stage actions and retained outcomes; no automatic write replay."
  alias Cadence.Management.Commanding.{
    StageCatalog,
    StageDrafts,
    StageItemAuthoring,
    StageSubmission
  }

  @writes ~w(edit_stage edit_details cancel_item save_item submit)
  def allowed?("commanding.stage-create", "create"), do: true

  def allowed?("commanding.stage-workbench", event),
    do: event in (@writes ++ ~w(preview_item preview_batch restart_draft))

  def allowed?(_, _), do: false

  def action(scope, session, "restart_draft", %{"expected_write" => expected} = input)
      when map_size(input) == 1 do
    {_, _, mission, _} = session.identity

    with %{status: "unconfirmed", event: event, write_token: ^expected} <- session.operation,
         true <- event != "submit" and session.id == "commanding.stage-workbench",
         {:ok, _} <- StageCatalog.workbench(scope, mission, session.stage_id, %{}) do
      notice =
        "The previous draft write remains unconfirmed. Review the current stored stage before making another edit."

      {%{status: "reset", notice: notice},
       %{
         session
         | write_token: StageDrafts.new_write_token(),
           operation: nil,
           item_preview: nil,
           batch_preview: nil,
           notice: notice
       }}
    else
      _ -> {rejected("Refresh the stage to check the previous write."), session}
    end
  end

  def action(scope, session, event, input) when event in ["preview_item", "preview_batch"] do
    if available?(session) do
      preview(scope, session, event, input)
    else
      {rejected("Refresh and check the previous write before preparing another change."), session}
    end
  end

  def action(scope, session, event, %{"expected_write" => expected} = input)
      when event in ["create" | @writes] do
    if allowed?(session.id, event) and available?(session) and expected == session.write_token do
      operation = %{status: "unconfirmed", event: event, write_token: expected}
      session = %{session | operation: operation}
      result = perform(scope, session, event, input)
      result = Map.merge(operation, result)
      {result, %{session | operation: result}}
    else
      {rejected(
         "This write token was consumed or replaced. Refresh to inspect the saved result."
       ), session}
    end
  end

  def action(_, session, _, _), do: {rejected("Invalid stage action."), session}

  defp available?(%{operation: %{write_token: token}, write_token: token}), do: false
  defp available?(_), do: true

  defp preview(scope, session, "preview_item", input) do
    {_, _, mission, _} = session.identity
    session = %{session | item_preview: nil}

    with true <- matches_command?(session.catalog, input["command"]),
         {:ok, held} <-
           StageItemAuthoring.preview(
             scope,
             mission,
             session.stage_id,
             selected_item(session),
             input
           ) do
      {%{status: "previewed", preview: StageItemAuthoring.public_preview(held)},
       %{session | item_preview: held}}
    else
      _ ->
        {rejected("Choose a current target and command, then review the draft again."), session}
    end
  rescue
    _ ->
      {rejected("The draft preview is unavailable. Refresh before trying again."),
       %{session | item_preview: nil}}
  end

  defp preview(scope, session, "preview_batch", input) do
    {_, _, mission, _} = session.identity
    session = %{session | batch_preview: nil}

    with true <- visible_selection?(session.model, input["items"]),
         {:ok, held} <- StageSubmission.preview(scope, mission, session.stage_id, input),
         {:ok, public} <- StageSubmission.public_preview(held) do
      {%{status: "previewed", preview: public}, %{session | batch_preview: held}}
    else
      _ ->
        {rejected(
           "The selected drafts changed or could not be validated. Refresh and select the current items."
         ), session}
    end
  rescue
    _ ->
      {rejected("The batch preview is unavailable. Refresh before trying again."),
       %{session | batch_preview: nil}}
  end

  defp perform(scope, session, event, input) do
    case write(scope, session, event, input) do
      {:ok, receipt} ->
        %{status: "completed", receipt: receipt}

      {:error, :command_stage_changed} ->
        rejected("The reviewed stage or item changed. Refresh and review its current contents.")

      {:error, :command_authoring_basis_changed} ->
        rejected("The command model or target changed. Refresh and review a new preview.")

      {:error, _} ->
        rejected("The change was not saved. Refresh the stage and check your access and inputs.")
    end
  rescue
    _ -> %{status: "unconfirmed"}
  catch
    _, _ -> %{status: "unconfirmed"}
  end

  defp write(scope, session, event, input) do
    {_, _, mission, _} = session.identity

    case event do
      "create" ->
        StageDrafts.create(scope, mission, session.creation, input)

      "edit_stage" ->
        StageDrafts.edit_stage(scope, mission, session.stage_id, session.write_token, input)

      "edit_details" ->
        StageDrafts.edit_details(
          scope,
          mission,
          session.stage_id,
          selected_item(session),
          session.write_token,
          input
        )

      "cancel_item" ->
        StageDrafts.cancel_item(
          scope,
          mission,
          session.stage_id,
          selected_item(session),
          session.write_token,
          input
        )

      "save_item" when is_map(session.item_preview) ->
        StageItemAuthoring.save(
          scope,
          mission,
          session.stage_id,
          session.write_token,
          session.item_preview,
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

      _ ->
        {:error, :command_stage_changed}
    end
  end

  defp selected_item(session) do
    case session.query["item"] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp matches_command?(catalog, input) when is_map(catalog) and is_map(input) do
    is_map(catalog["selected_command"]) and catalog["selected_command"]["supported"] and
      is_map(catalog["selected_target"]) and
      input["expected_basis"] == catalog["basis"]["token"] and
      input["command_id"] == catalog["selected_command"]["id"] and
      input["source_endpoint_ref"] == catalog["selected_target"]["id"]
  end

  defp matches_command?(_, _), do: false

  defp visible_selection?(model, items) when is_map(model) and is_list(items) do
    entries = get_in(model, ["items", "entries"]) || []

    length(items) in 1..25 and
      Enum.all?(items, fn item ->
        is_map(item) and
          Enum.any?(
            entries,
            &(&1["id"] == item["id"] and &1["expected_item"] == item["expected_item"])
          )
      end)
  end

  defp visible_selection?(_, _), do: false
  defp rejected(message), do: %{status: "rejected", feedback: message}
end
