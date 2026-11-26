defmodule Cadence.Catalog.ConfigurationReviews do
  @moduledoc """
  The per-spacecraft evidence of a configuration review: which saved version of each
  spacecraft's configuration was reviewed, under which token (#734).

  Like the fleet (`Cadence.Catalog.FleetSnapshot`), the evidence is stored once, by content hash,
  and the activation metadata carries only a constant-size reference:

      "configuration_review" => %{
        "review" => %{"mission_id" => _, "sha256" => _, "count" => _},
        "base_activation_id" => _
      }

  A review of one spacecraft is a review set of one. There is no cap on a set's size; inserts
  are chunked.
  """

  import Ecto.Query

  alias Cadence.Catalog.ConfigurationReviews.{MemberRow, SetRow}
  alias Cadence.Platform.ContentHash
  alias Cadence.Repo

  @chunk 1_000
  @stale {:error, :spacecraft_configuration_review_stale}

  @type review_ref :: %{required(String.t()) => term()}
  @type item :: %{
          required(:id) => String.t(),
          required(:configuration_revision_id) => String.t(),
          required(:configuration_token) => String.t()
        }

  @doc """
  Stores a review set (idempotent: an identical set re-uses its rows) and returns its reference.
  """
  @spec store(String.t(), [item()]) :: {:ok, review_ref()} | {:error, term()}
  def store(mission_id, [_ | _] = items) when is_binary(mission_id) do
    members =
      items
      |> Enum.map(&{&1.id, &1.configuration_revision_id, &1.configuration_token})
      |> Enum.sort()

    sha = ContentHash.term_sha256(members)

    case Repo.transaction(fn -> persist(mission_id, sha, members) end) do
      {:ok, :ok} ->
        {:ok, %{"mission_id" => mission_id, "sha256" => sha, "count" => length(members)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The `configuration_review` metadata value for a stored set."
  @spec metadata(review_ref(), String.t() | nil) :: map()
  def metadata(reference, base_activation_id),
    do: %{"review" => reference, "base_activation_id" => base_activation_id}

  @doc "Whether the metadata is a configuration review."
  @spec reviewed?(map()) :: boolean()
  def reviewed?(%{"configuration_review" => %{"review" => %{}}}), do: true
  def reviewed?(_metadata), do: false

  @doc "The reviewed spacecraft ids, sorted."
  @spec spacecraft_ids(map()) ::
          {:ok, [String.t()]} | {:error, :spacecraft_configuration_review_stale}
  def spacecraft_ids(metadata) do
    with {:ok, query, _count} <- members_query(metadata) do
      # Sorted in Elixir (bytewise), whatever the database's text collation (#56).
      {:ok, query |> select([m], m.spacecraft_id) |> Repo.all() |> Enum.sort()}
    end
  end

  @doc """
  Every reviewed spacecraft's evidence, `spacecraft_id => %{"spacecraft_id", "configuration_revision_id",
  "configuration_token", "base_activation_id"}`: one query.
  """
  @spec evidence(map()) ::
          {:ok, %{String.t() => map()}} | {:error, :spacecraft_configuration_review_stale}
  def evidence(metadata) do
    with {:ok, query, count} <- members_query(metadata) do
      base = get_in(metadata, ["configuration_review", "base_activation_id"])

      evidence =
        query
        |> select([m], {m.spacecraft_id, m.configuration_revision_id, m.configuration_token})
        |> Repo.all()
        |> Map.new(fn {id, revision_id, token} ->
          {id,
           %{
             "spacecraft_id" => id,
             "configuration_revision_id" => revision_id,
             "configuration_token" => token,
             "base_activation_id" => base
           }}
        end)

      if map_size(evidence) == count, do: {:ok, evidence}, else: @stale
    end
  end

  @doc "One spacecraft's evidence (shape of `evidence/1`), or nil when it wasn't reviewed."
  @spec evidence_for(map(), String.t()) :: map() | nil
  def evidence_for(metadata, spacecraft_id) do
    with {:ok, query, _count} <- members_query(metadata),
         {revision_id, token} <-
           query
           |> where([m], m.spacecraft_id == ^spacecraft_id)
           |> select([m], {m.configuration_revision_id, m.configuration_token})
           |> Repo.one() do
      %{
        "spacecraft_id" => spacecraft_id,
        "configuration_revision_id" => revision_id,
        "configuration_token" => token,
        "base_activation_id" => get_in(metadata, ["configuration_review", "base_activation_id"])
      }
    else
      _not_reviewed -> nil
    end
  end

  defp members_query(%{
         "configuration_review" => %{
           "review" => %{"mission_id" => mission_id, "sha256" => sha} = ref
         }
       })
       when is_binary(mission_id) and is_binary(sha) do
    {:ok, where(MemberRow, [m], m.mission_id == ^mission_id and m.review_sha256 == ^sha),
     Map.get(ref, "count")}
  end

  defp members_query(_metadata), do: @stale

  defp persist(mission_id, sha, members) do
    now = DateTime.utc_now()

    if Repo.exists?(where(SetRow, [s], s.mission_id == ^mission_id and s.review_sha256 == ^sha)) do
      :ok
    else
      members
      |> Enum.map(fn {id, revision_id, token} ->
        %{
          mission_id: mission_id,
          review_sha256: sha,
          spacecraft_id: id,
          configuration_revision_id: revision_id,
          configuration_token: token
        }
      end)
      |> Enum.chunk_every(@chunk)
      |> Enum.each(&Repo.insert_all(MemberRow, &1, on_conflict: :nothing))

      Repo.insert_all(
        SetRow,
        [
          %{
            mission_id: mission_id,
            review_sha256: sha,
            spacecraft_count: length(members),
            inserted_at: now
          }
        ],
        on_conflict: :nothing
      )

      :ok
    end
  end
end
