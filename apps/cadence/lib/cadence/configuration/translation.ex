defmodule Cadence.Configuration.Translation do
  @moduledoc """
  A kind's staging-time rewrite of an op (`ConfigKind.translate/5`), run before `normalize/3` with
  the tenant in hand. Staging only: apply validates what was staged and never translates (D3,
  #544: an old client's `catalog_revision_id` becomes the composition it names here, so the staged
  op is what's reviewed and applied).
  """

  alias Cadence.Configuration.Document

  @doc "A create's document, translated."
  @spec document(module(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, [map()]}
  def document(kind, organization_id, mission_id, document) do
    if translates?(kind),
      do: kind.translate(organization_id, mission_id, nil, document, Map.keys(document)),
      else: {:ok, document}
  end

  @doc """
  An update's changes, plus a change for every top-level path the translation sets beyond them.
  """
  @spec changes(module(), String.t(), String.t(), map(), [map()]) ::
          {:ok, [map()]} | {:error, [map()]}
  def changes(kind, organization_id, mission_id, current, changes) do
    if translates?(kind) do
      proposed = Document.patch(current, changes)
      touched = Enum.map(changes, & &1["path"])

      with {:ok, translated} <-
             kind.translate(organization_id, mission_id, current, proposed, touched) do
        {:ok, changes ++ further(proposed, translated, touched)}
      end
    else
      {:ok, changes}
    end
  end

  defp further(proposed, translated, touched) do
    for key <- Enum.uniq(Map.keys(proposed) ++ Map.keys(translated)),
        key not in touched,
        Map.get(proposed, key) != Map.get(translated, key),
        do: %{"path" => key, "value" => Map.get(translated, key)}
  end

  defp translates?(kind), do: function_exported?(kind, :translate, 5)
end
