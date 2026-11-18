defmodule CadenceWeb.Console.SpacecraftWorkspaceWords do
  @moduledoc """
  ux's U94 words for the configuration workspace's refusals: the CONSOLE routes' messages only.
  The host still renders its own spacecraft configuration page, so its copy stays as it is, and
  the shared `Problem` table (L10 and others use some of these codes) is left alone.

  `ctx`: `name` (the craft's display name, nil for an unknown craft) and, for the model gate's
  refusal only, `catalog` ("catalog rev 14"). Without them the words say "this spacecraft" or
  "the catalog revision", never an id; `spacecraft_catalog_unavailable` always says "that catalog
  revision" (a revision outside the mission has no number here).

  A refusal both a save and a submit can return opens with "Not saved:" or "Not sent:" by action.
  """

  @doc "The console's sentence for `code` on `action` (:show | :save | :submit | :packets), or nil."
  @spec message(atom(), atom(), map()) :: binary() | nil
  def message(:spacecraft_configuration_changed, _action, ctx),
    do:
      "Not saved: someone saved #{possessive(ctx)} configuration after you started editing. " <>
        "Your edits are kept; choose which version to keep."

  def message(:spacecraft_configuration_review_unavailable, _action, _ctx),
    do: "Not sent: save the draft and choose which version to keep first."

  def message(:spacecraft_configuration_review_stale, _action, ctx),
    do:
      "Not sent: #{possessive(ctx)} active configuration changed since you loaded this. " <>
        "Check the comparison and send it again."

  def message(:activation_policy_changed, _action, _ctx),
    do: "Not sent: the mission's approval setting changed. Check it and send it again."

  # A change set flipped a switch after the draft was saved (Review.request's check); the save
  # side keeps the shared line (ux).
  def message(:spacecraft_switch_set_by_change_set, :submit, ctx),
    do:
      "Not sent: a change set turned Telemetry or Commanding on or off for #{name(ctx)} after " <>
        "this draft was saved. Save the draft again, then send it."

  def message(:spacecraft_catalog_set_by_profile, action, ctx),
    do:
      "#{not_done(action)} #{possessive(ctx)} profile sets its catalog revision. " <>
        "Change it on the profile, through Setup › Changes."

  def message(:mission_model_revision_not_approved, _action, ctx) do
    {label, verb, pronoun} =
      case ctx[:catalog] do
        "catalog revs " <> _ = label -> {label, "aren't", "them"}
        nil -> {"the catalog revision", "isn't", "it"}
        label -> {label, "isn't", "it"}
      end

    "Not sent: #{label} #{verb} approved yet. " <>
      "An org admin approves #{pronoun} in Setup › Catalog first."
  end

  def message(:spacecraft_catalog_required, _action, _ctx),
    do: "Not sent: choose a catalog revision first."

  def message(:spacecraft_packet_inputs_required, _action, ctx),
    do:
      "Not sent: telemetry is on for #{name(ctx)}, so choose a packet source and the APIDs " <>
        "to decode first."

  def message(:spacecraft_catalog_unavailable, action, _ctx),
    do:
      "#{not_done(action)} that catalog revision isn't one of this mission's catalog revisions. " <>
        "Choose another."

  def message(:spacecraft_packet_input_unavailable, _action, ctx),
    do:
      "Not saved: the packet source you chose isn't available to #{name(ctx)} any more. " <>
        "Choose another."

  def message(:spacecraft_source_limit_exceeded, _action, ctx),
    do:
      "#{capitalized(name(ctx))} has more packet sources than one configuration can carry, " <>
        "so it can't be shown or sent. Remove some in Setup › Comms."

  def message(:invalid_document, _action, _ctx),
    do: "Not saved: Cadence couldn't read this draft. Reload and try again."

  def message(:invalid_params, :save, _ctx), do: "Not saved."
  def message(:invalid_params, :submit, _ctx), do: "Not sent."

  def message(:forbidden, _action, ctx),
    do: "You can't change #{possessive(ctx)} configuration."

  def message(:spacecraft_not_found, _action, ctx),
    do: "#{capitalized(name(ctx))} isn't on this mission."

  def message(:catalog_revision_not_found, :packets, _ctx),
    do: "This catalog revision isn't in the mission's catalog any more. Choose another."

  def message(_code, _action, _ctx), do: nil

  @doc ~s(Catalog revisions as ux names them, in number order: "catalog rev 14"; "catalog revs 4 and 5".)
  def catalog_label([]), do: nil
  def catalog_label([number]) when is_integer(number), do: "catalog rev #{number}"

  def catalog_label(numbers) when is_list(numbers) do
    case numbers |> Enum.filter(&is_integer/1) |> Enum.uniq() |> Enum.sort() do
      [] -> nil
      [one] -> catalog_label([one])
      many -> "catalog revs " <> Enum.join(Enum.drop(many, -1), ", ") <> " and #{List.last(many)}"
    end
  end

  defp not_done(:submit), do: "Not sent:"
  defp not_done(_save), do: "Not saved:"

  defp name(%{name: name}) when is_binary(name), do: name
  defp name(_ctx), do: "this spacecraft"

  defp possessive(ctx), do: name(ctx) <> "'s"

  defp capitalized("this spacecraft"), do: "This spacecraft"
  defp capitalized(name), do: name
end
