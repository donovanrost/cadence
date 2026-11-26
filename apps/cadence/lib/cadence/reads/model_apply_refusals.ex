defmodule Cadence.Reads.ModelApplyRefusals do
  @moduledoc """
  The words for an apply the model approval gate refused (ux U65; domain's
  `Control.ModelApprovalGate`): the preview's blocking hold normally says it first. A model is
  named by its catalog revision ("catalog rev 4"); the ids stay in details.

    * `mission_model_revision_not_approved`: "Not applied: catalog rev 4 isn't approved yet."
    * `mission_model_comparison_failed`: "Not applied: catalog rev 4's comparison didn't pass."
  """

  alias Cadence.Catalog.ModelRevisions

  @spec numbers(binary() | nil, binary() | nil, [binary()]) :: %{binary() => integer() | nil}
  def numbers(organization_id, mission_id, revision_ids)
      when is_binary(organization_id) and is_binary(mission_id) do
    found = ModelRevisions.for_models(organization_id, mission_id, revision_ids)
    Map.new(revision_ids, &{&1, get_in(found, [&1, :number])})
  end

  def numbers(_organization_id, _mission_id, revision_ids),
    do: Map.new(revision_ids, &{&1, nil})

  @typedoc """
  A refusal as data (api-ops, ca-ux on #556), so callers word it per act without parsing a
  sentence: `why` is the reason clause (no opener, no period), and `subject` is what an approver
  waits on: one named catalog revision, one whose number isn't known, or several.
  """
  @type refusal :: %{
          required(:why) => binary(),
          optional(:subject) => {:one, binary()} | :unknown | :many
        }

  @spec refusal(atom(), [integer() | nil]) :: refusal()
  def refusal(:mission_model_revision_not_approved, [nil]),
    do: %{why: "#{rev(nil)} isn't approved yet", subject: :unknown}

  def refusal(:mission_model_revision_not_approved, [number]),
    do: %{why: "#{rev(number)} isn't approved yet", subject: {:one, rev(number)}}

  def refusal(:mission_model_revision_not_approved, numbers),
    do: %{why: "#{revs(numbers)} aren't approved yet", subject: :many}

  def refusal(:mission_model_comparison_failed, [number]),
    do: %{why: "#{rev(number)}'s comparison didn't pass"}

  @doc "The apply refusal's sentence: \"Not applied: \" and the reason."
  @spec sentence(atom(), [integer() | nil]) :: binary()
  def sentence(tag, numbers), do: "Not applied: " <> refusal(tag, numbers).why <> "."

  defp rev(nil), do: "a catalog revision"
  defp rev(number), do: "catalog rev #{number}"

  defp revs(numbers) do
    case Enum.reject(numbers, &is_nil/1) do
      [] -> "#{length(numbers)} catalog revisions"
      known -> "catalog revs " <> join(Enum.map(known, &to_string/1))
    end
  end

  defp join([a, b]), do: "#{a} and #{b}"
  defp join(items), do: Enum.join(Enum.drop(items, -1), ", ") <> " and " <> List.last(items)
end
