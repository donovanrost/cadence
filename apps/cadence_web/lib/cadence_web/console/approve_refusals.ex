defmodule CadenceWeb.Console.ApproveRefusals do
  @moduledoc """
  The activation approve preflight's refusals on the console (ux U95; domain's one check list,
  director 11-17): each a 409 with its own code, nothing recorded. The messages are U95's lines
  in the forms that need no details (the console words the detailed forms from `details`); a code
  U95 doesn't word gets the generic line. Kept apart from `Problem`'s table: the same codes mean
  something else on the model approval (U88), with other words.
  """

  import Plug.Conn

  alias CadenceWeb.Console.Problem

  @recorded " Your approval wasn't recorded."

  @messages %{
    approved_activation_content_mismatch:
      "Not approved: what this request would apply changed after it was requested, so it isn't what you reviewed. The requester sends it again.",
    mission_model_revision_not_approved:
      "Not approved: a catalog revision it uses isn't approved yet, so this can't apply. An org admin approves it in Setup, Catalog first.",
    mission_model_revision_not_in_catalog:
      "Not approved: the catalog doesn't list the revision this request uses, so it can't apply. The requester sends a request for a revision the catalog lists.",
    mission_model_comparison_failed:
      "Not approved: the comparison for the catalog revision it uses didn't pass, so this can't apply.",
    spacecraft_configuration_review_stale:
      "Not approved: a spacecraft's configuration changed after this was requested, so it isn't what was reviewed. The requester sends it again.",
    change_set_activation_stale:
      "Not approved: what's running on this mission changed after this was requested, so it isn't what was reviewed. The requester sends it again.",
    mission_model_activation_manifest_required:
      "Not approved: this request doesn't say which catalog revision it activates, so it can't apply. The requester sends it again; if it keeps happening, tell the team that runs Cadence.",
    mission_model_comparison_report_required:
      "Not approved: the catalog revision it uses hasn't been compared yet. Run the comparison in Setup, Catalog first.",
    mission_model_runtime_plans_not_ready:
      "Not approved: Cadence is still preparing the catalog revision it uses. Try again in a moment.",
    spacecraft_configuration_review_required:
      "Not approved: on this mission, changes are activated from each spacecraft's configuration (Setup, Spacecraft), so this request can't apply. Reject it, and send the change from the spacecraft's configuration instead.",
    spacecraft_model_not_active:
      "Not approved: the catalog revision a spacecraft was reviewed with isn't the active one any more, so this isn't what was reviewed. The requester sends it again."
  }

  @generic "Not approved: this request can't apply as it stands."

  @doc """
  #236 (ux): an author of the configuration being activated is refused (403), naming up to three
  of the spacecraft they saved, then "and N more". Without names, the generic line.
  """
  @spec authored(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def authored(conn, %{spacecraft_ids: ids, spacecraft: named} = details) do
    names = named |> Enum.map(& &1.name) |> Enum.filter(&is_binary/1) |> Enum.take(3)
    {status, code, generic} = Problem.describe(:activation_approver_authored_content)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(
      Problem.body(code, authored_line(names, length(ids)) || generic, details)
    )
    |> halt()
  end

  defp authored_line([], _count), do: nil

  defp authored_line([name], 1),
    do:
      "Not approved: you saved #{name}'s configuration in this request, so another person approves it." <>
        @recorded

  defp authored_line(names, count) when length(names) == count,
    do: authored_many(Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names))

  defp authored_line(names, count),
    do: authored_many(Enum.join(names, ", ") <> " and #{count - length(names)} more spacecraft")

  defp authored_many(list),
    do:
      "Not approved: you saved the configurations of #{list} in this request, so another person approves it." <>
        @recorded

  @spec respond(Plug.Conn.t(), atom(), map() | nil) :: Plug.Conn.t()
  def respond(conn, code, details) when is_atom(code) do
    message = Map.get(@messages, code, @generic) <> @recorded

    conn
    |> put_status(409)
    |> Phoenix.Controller.json(Problem.body(Atom.to_string(code), message, details))
    |> halt()
  end
end
