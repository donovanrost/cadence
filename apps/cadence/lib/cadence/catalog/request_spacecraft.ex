defmodule Cadence.Catalog.RequestSpacecraft do
  @moduledoc """
  The spacecraft an activation request covers, whichever kind wrote its metadata (#734): a
  configuration review (`Catalog.ConfigurationReviews`), a change set's generation
  (`Catalog.ChangeSetSpacecraft`), or a single triggering spacecraft. The metadata holds only
  references and counts, so a list of requests costs no query for its counts, and one query per
  kind to ask which of them touch a spacecraft.
  """

  alias Cadence.Catalog.{ChangeSetSpacecraft, ConfigurationReviews}

  @doc "How many spacecraft the request covers, from its metadata alone; nil when unknown."
  @spec count(map()) :: non_neg_integer() | nil
  def count(metadata) when is_map(metadata) do
    ChangeSetSpacecraft.count(metadata) || ConfigurationReviews.count(metadata) ||
      if(is_binary(metadata["triggering_spacecraft_id"]), do: 1)
  end

  def count(_metadata), do: nil

  @doc "The covered spacecraft ids, sorted; `[]` for a request that names none or can't be read."
  @spec ids(String.t(), String.t(), map()) :: [String.t()]
  def ids(organization_id, mission_id, metadata) when is_map(metadata) do
    cond do
      ChangeSetSpacecraft.change_set?(metadata) ->
        ChangeSetSpacecraft.spacecraft_ids(organization_id, mission_id, metadata)

      is_binary(metadata["triggering_spacecraft_id"]) ->
        [metadata["triggering_spacecraft_id"]]

      true ->
        case ConfigurationReviews.spacecraft_ids(organization_id, mission_id, metadata) do
          {:ok, ids} -> ids
          {:error, _unreadable} -> []
        end
    end
  end

  def ids(_organization_id, _mission_id, _metadata), do: []

  @doc """
  A predicate over `requests` (maps with `:metadata`): whether a request touches `spacecraft_id`.
  A request that names no spacecraft (another kind) touches all of them. Two queries at most,
  however many requests.
  """
  @spec touching(String.t(), String.t(), [map()], String.t()) :: (map() -> boolean())
  def touching(organization_id, mission_id, requests, spacecraft_id) do
    metadata = Enum.map(requests, &(&1.metadata || %{}))

    reviews =
      ConfigurationReviews.covering(
        organization_id,
        mission_id,
        metadata |> Enum.map(&ConfigurationReviews.sha/1) |> Enum.reject(&is_nil/1),
        spacecraft_id
      )

    change_sets =
      ChangeSetSpacecraft.covering(
        organization_id,
        mission_id,
        for(%{"change_set" => %{"id" => id, "revision" => rev}} <- metadata, do: {id, rev}),
        spacecraft_id
      )

    fn request ->
      metadata = request.metadata || %{}

      cond do
        ChangeSetSpacecraft.change_set?(metadata) ->
          {metadata["change_set"]["id"], metadata["change_set"]["revision"]} in change_sets

        is_binary(metadata["triggering_spacecraft_id"]) ->
          metadata["triggering_spacecraft_id"] == spacecraft_id

        sha = ConfigurationReviews.sha(metadata) ->
          sha in reviews

        true ->
          true
      end
    end
  end
end
