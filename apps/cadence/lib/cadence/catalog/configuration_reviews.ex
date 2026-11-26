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

  Every read takes the request's own organization and mission. A reference naming another
  mission is refused (`:spacecraft_configuration_review_stale`), and both tables are filtered on
  organization and mission, so one tenant's metadata can never read another's evidence.
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
  The set is read back inside the transaction: a set that isn't exactly what was asked for is an
  error, never a reference.
  """
  @spec store(String.t(), String.t(), [item()]) :: {:ok, review_ref()} | {:error, term()}
  def store(organization_id, mission_id, [_ | _] = items)
      when is_binary(organization_id) and is_binary(mission_id) do
    members =
      items
      |> Enum.map(&{&1.id, &1.configuration_revision_id, &1.configuration_token})
      |> Enum.sort()

    sha = ContentHash.term_sha256(members)

    case Repo.transaction(fn -> persist(organization_id, mission_id, sha, members) end) do
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

  @doc "How many spacecraft the review covers, from the reference alone (no query)."
  @spec count(map()) :: non_neg_integer() | nil
  def count(%{"configuration_review" => %{"review" => %{"count" => count}}})
      when is_integer(count) and count > 0,
      do: count

  def count(_metadata), do: nil

  @doc """
  The reviewed spacecraft ids, sorted. The members are re-hashed against the reference's sha (see
  `evidence/3`).
  """
  @spec spacecraft_ids(String.t(), String.t(), map()) ::
          {:ok, [String.t()]} | {:error, :spacecraft_configuration_review_stale}
  def spacecraft_ids(organization_id, mission_id, metadata) do
    with {:ok, rows} <- verified(organization_id, mission_id, metadata) do
      # Sorted in Elixir (bytewise), whatever the database's text collation (#56).
      {:ok, rows |> Enum.map(&elem(&1, 0)) |> Enum.sort()}
    end
  end

  @doc """
  Every reviewed spacecraft's evidence, `spacecraft_id => %{"spacecraft_id", "configuration_revision_id",
  "configuration_token", "base_activation_id"}`: one query. The evidence an approval rests on is
  verified: the members are re-hashed (`ContentHash.term_sha256` over the sorted `{id, revision,
  token}` tuples, as `store/3` hashed them) and compared with the reference's sha, so a row changed
  or swapped after the review reads as stale, not as what was approved.
  """
  @spec evidence(String.t(), String.t(), map()) ::
          {:ok, %{String.t() => map()}} | {:error, :spacecraft_configuration_review_stale}
  def evidence(organization_id, mission_id, metadata) do
    with {:ok, rows} <- verified(organization_id, mission_id, metadata) do
      base = get_in(metadata, ["configuration_review", "base_activation_id"])

      {:ok,
       Map.new(rows, fn {id, revision_id, token} ->
         {id,
          %{
            "spacecraft_id" => id,
            "configuration_revision_id" => revision_id,
            "configuration_token" => token,
            "base_activation_id" => base
          }}
       end)}
    end
  end

  @doc """
  One spacecraft's evidence (shape of `evidence/3`), or nil when it wasn't reviewed. A display and
  staleness read of one row: it doesn't re-hash the set, so an approval or admission reads
  `evidence/3`.
  """
  @spec evidence_for(String.t(), String.t(), map(), String.t()) :: map() | nil
  def evidence_for(organization_id, mission_id, metadata, spacecraft_id) do
    with {:ok, query, _count, _sha} <- members_query(organization_id, mission_id, metadata),
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

  @doc """
  The review shas (from `metadata` values) among `shas` that cover `spacecraft_id`, in one query:
  which of a list of requests touch a spacecraft.
  """
  @spec covering(String.t(), String.t(), [String.t()], String.t()) :: MapSet.t(String.t())
  def covering(_organization_id, _mission_id, [], _spacecraft_id), do: MapSet.new()

  def covering(organization_id, mission_id, shas, spacecraft_id) do
    organization_id
    |> member_shas(mission_id, spacecraft_id)
    |> where([m], m.review_sha256 in ^shas)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  A query of the review shas that cover `spacecraft_id` (indexed by spacecraft), for another context to
  filter its own rows by without reaching into this context's persistence rows.
  """
  @spec member_shas(String.t(), String.t(), String.t()) :: Ecto.Query.t()
  def member_shas(organization_id, mission_id, spacecraft_id) do
    from(m in MemberRow,
      where:
        m.organization_id == ^organization_id and m.mission_id == ^mission_id and
          m.spacecraft_id == ^spacecraft_id,
      select: m.review_sha256
    )
  end

  @doc "The review's own sha, or nil."
  @spec sha(map()) :: String.t() | nil
  def sha(%{"configuration_review" => %{"review" => %{"sha256" => sha}}}) when is_binary(sha),
    do: sha

  def sha(_metadata), do: nil

  # Loads the set and checks it is what the reference names: the count and the content hash.
  defp verified(organization_id, mission_id, metadata) do
    with {:ok, query, count, sha} <- members_query(organization_id, mission_id, metadata) do
      rows =
        query
        |> select([m], {m.spacecraft_id, m.configuration_revision_id, m.configuration_token})
        |> Repo.all()
        |> Enum.sort()

      if length(rows) == count and ContentHash.term_sha256(rows) == sha,
        do: {:ok, rows},
        else: @stale
    end
  end

  defp members_query(organization_id, mission_id, %{
         "configuration_review" => %{
           "review" => %{"mission_id" => mission_id, "sha256" => sha, "count" => count}
         }
       })
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(sha) and
              is_integer(count) do
    {:ok,
     where(
       MemberRow,
       [m],
       m.organization_id == ^organization_id and m.mission_id == ^mission_id and
         m.review_sha256 == ^sha
     ), count, sha}
  end

  # Anything else, including a reference that names another mission, is not this request's.
  defp members_query(_organization_id, _mission_id, _metadata), do: @stale

  defp persist(organization_id, mission_id, sha, members) do
    now = DateTime.utc_now()

    unless Repo.exists?(
             where(
               SetRow,
               [s],
               s.organization_id == ^organization_id and s.mission_id == ^mission_id and
                 s.review_sha256 == ^sha
             )
           ) do
      members
      |> Enum.map(fn {id, revision_id, token} ->
        %{
          organization_id: organization_id,
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
            organization_id: organization_id,
            mission_id: mission_id,
            review_sha256: sha,
            spacecraft_count: length(members),
            inserted_at: now
          }
        ],
        on_conflict: :nothing
      )
    end

    stored =
      Repo.aggregate(
        where(
          MemberRow,
          [m],
          m.organization_id == ^organization_id and m.mission_id == ^mission_id and
            m.review_sha256 == ^sha
        ),
        :count
      )

    if stored == length(members),
      do: :ok,
      else: Repo.rollback(:spacecraft_configuration_review_stale)
  end
end
