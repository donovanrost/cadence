defmodule Cadence.Governance.Accountability do
  @moduledoc """
  Who counts as "self" for separation of duties (#280, director 11-19). Every approval kind that
  already refuses self-approval compares its approver with `authors/2` through `approvers/3`
  instead of comparing person ids directly. It widens who counts as self and never adds a refusal
  to a kind or mode that doesn't refuse today.

  - A person is themselves.
  - A service identity is every person accountable for it (`Auth.ServiceAccountability`): its
    issuer and every rotator, transitively. If that set isn't known, the whole result is
    `{:error, :unknown}` and the caller refuses with its kind's `*_approver_authors_unknown` (403).
  - Anything else (the system actor, an empty legacy `%{}`) counts no one, as before (MM-2 is
    tracked separately).

  Actors may be given as the documents the kinds store (`%{"actor_kind" => "user", "user_id" => id}`,
  `%{"kind" => "service", "id" => id}`, …) or as `{:user, id}` / `{:service, id}`.
  """

  import Ecto.Query

  alias Cadence.Auth.{ServiceAccountability, ServiceIdentityRow}
  alias Cadence.Repo

  @type actor :: map() | {:user, binary()} | {:service, binary()} | nil

  @doc "The people the given authors count as."
  @spec authors(binary(), [actor()]) :: {:ok, [binary()]} | {:error, :unknown}
  def authors(organization_id, actors) when is_binary(organization_id) and is_list(actors) do
    Enum.reduce_while(actors, {:ok, MapSet.new()}, fn actor, {:ok, acc} ->
      case people(organization_id, normalize(actor)) do
        {:ok, ids} -> {:cont, {:ok, MapSet.union(acc, MapSet.new(ids))}}
        {:error, :unknown} -> {:halt, {:error, :unknown}}
      end
    end)
    |> case do
      {:ok, set} -> {:ok, set |> MapSet.to_list() |> Enum.sort()}
      error -> error
    end
  end

  @doc """
  The people an approver counts as: a person is themselves; a service approving under an
  automation grant is its accountable people plus the grant's people (`grant_approver`: a user id
  or a list of them, the grant's proposer and approver since #283; nil when there's no grant).
  """
  @spec approvers(binary(), actor(), binary() | [binary() | nil] | nil) ::
          {:ok, [binary()]} | {:error, :unknown}
  def approvers(organization_id, approver, grant_approver \\ nil) do
    authors(organization_id, [approver | grant_actors(grant_approver)])
  end

  @typedoc "A service identity named in a refusal's details: `%{id, name}`."
  @type service_ref :: %{id: binary(), name: binary() | nil}

  @doc """
  `:ok` when the approver's people and the authors' people don't meet. Otherwise:

  - `{:error, {:self, via}}`: they meet. `via` is nil when an author is the approver themselves
    (their own act wins), else the service identity whose accountable people include them.
  - `{:error, {:unknown, service}}`: a service on either side has no accountable people on record,
    so nobody can approve (fail closed). `service` names it.
  """
  @spec separate(binary(), actor(), [actor()], binary() | [binary() | nil] | nil) ::
          :ok | {:error, {:self, service_ref() | nil} | {:unknown, service_ref()}}
  def separate(organization_id, approver, authors, grant_approver \\ nil) do
    approver_actors = [approver | grant_actors(grant_approver)] |> Enum.map(&normalize/1)

    with {:ok, approving} <- resolve_all(organization_id, approver_actors),
         {:ok, authoring} <- resolve_all(organization_id, Enum.map(authors, &normalize/1)) do
      approving_people = approving |> Enum.flat_map(&elem(&1, 1)) |> MapSet.new()

      overlapping =
        Enum.filter(authoring, fn {_actor, people} ->
          not MapSet.disjoint?(approving_people, MapSet.new(people))
        end)

      cond do
        overlapping == [] -> :ok
        Enum.any?(overlapping, &match?({{:user, _}, _}, &1)) -> {:error, {:self, nil}}
        true -> {:error, {:self, overlapping |> hd() |> elem(0) |> service_ref(organization_id)}}
      end
    end
  end

  @doc """
  `separate/4`'s result as a kind's refusal (api 11-19):

  - `self_code` alone when the approver did it themselves (unchanged from before #280; the web
    layer sends `details.via_service: null`);
  - `{self_code, %{via_service: ref}}` when it came through a service;
  - `{unknown_code, %{service: ref}}` when a set is unknown (a 403 per kind, e.g.
    `:activation_approver_authors_unknown`).
  """
  @spec refusal(:ok | {:error, term()}, atom(), atom()) :: :ok | {:error, term()}
  def refusal(:ok, _self_code, _unknown_code), do: :ok
  def refusal({:error, {:self, nil}}, self_code, _unknown_code), do: {:error, self_code}

  def refusal({:error, {:self, via}}, self_code, _unknown_code),
    do: {:error, {self_code, %{via_service: via}}}

  def refusal({:error, {:unknown, service}}, _self_code, unknown_code),
    do: {:error, {unknown_code, %{service: service}}}

  defp grant_actors(ids) when is_list(ids), do: Enum.flat_map(ids, &grant_actors/1)
  defp grant_actors(id) when is_binary(id) and id != "", do: [{:user, id}]
  defp grant_actors(_id), do: []

  defp resolve_all(organization_id, actors) do
    Enum.reduce_while(actors, {:ok, []}, fn actor, {:ok, acc} ->
      case people(organization_id, actor) do
        {:ok, ids} ->
          {:cont, {:ok, [{actor, ids} | acc]}}

        {:error, :unknown} ->
          {:halt, {:error, {:unknown, service_ref(actor, organization_id)}}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp service_ref({:service, id}, organization_id) do
    name =
      ServiceIdentityRow
      |> where([row], row.organization_id == ^organization_id and row.service_identity_id == ^id)
      |> select([row], row.display_name)
      |> Repo.one()

    %{id: id, name: name}
  end

  @doc """
  Actors for the bare ids some kinds store (a contact plan's `created_by`, `lifecycle_changed_by`):
  each id counts as that person and, when a service identity in the organization has that id, as
  that service too. Counting both can only widen who is "self", never narrow it.
  """
  @spec actors_for_ids(binary(), [binary() | nil]) :: [{:user, binary()} | {:service, binary()}]
  def actors_for_ids(organization_id, ids) when is_binary(organization_id) and is_list(ids) do
    ids = ids |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq()

    services =
      ServiceIdentityRow
      |> where([row], row.organization_id == ^organization_id and row.service_identity_id in ^ids)
      |> select([row], row.service_identity_id)
      |> Repo.all()

    Enum.map(ids, &{:user, &1}) ++ Enum.map(services, &{:service, &1})
  end

  @doc """
  The ids of `actors` (a service by its own id), sorted and unique: what a four-eyes record's
  `separated_from` stores for the authors a separation check was given (#117).
  """
  @spec ids([term()]) :: [binary()]
  def ids(actors) do
    actors
    |> Enum.flat_map(fn actor ->
      case normalize(actor) do
        {_kind, id} -> [id]
        :none -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Whether any of `actors` is a service identity (its people come from its record)."
  @spec any_service?([actor()]) :: boolean()
  def any_service?(actors), do: Enum.any?(actors, &match?({:service, _}, normalize(&1)))

  defp people(_organization_id, {:user, id}), do: {:ok, [id]}

  defp people(organization_id, {:service, id}),
    do: ServiceAccountability.people(organization_id, id)

  defp people(_organization_id, :none), do: {:ok, []}

  @doc false
  @spec normalize(actor()) :: {:user, binary()} | {:service, binary()} | :none
  def normalize({kind, id}) when kind in [:user, :service] and is_binary(id) and id != "",
    do: {kind, id}

  def normalize(%{"actor_kind" => "service", "service_identity_id" => id}), do: service(id)
  def normalize(%{"kind" => "service", "service_identity_id" => id}), do: service(id)
  def normalize(%{"kind" => "service", "id" => id}), do: service(id)
  def normalize(%{"actor_kind" => "service", "id" => id}), do: service(id)
  def normalize(%{"actor_kind" => "user", "user_id" => id}), do: user(id)
  def normalize(%{"kind" => "user", "user_id" => id}), do: user(id)
  def normalize(%{"kind" => "user", "id" => id}), do: user(id)
  def normalize(%{"actor_kind" => kind}) when kind not in ["user", nil], do: :none
  def normalize(%{"kind" => kind}) when kind not in ["user", nil], do: :none
  def normalize(%{"user_id" => id}), do: user(id)
  def normalize(%{user_id: id}), do: user(id)
  def normalize(id) when is_binary(id) and id != "", do: {:user, id}
  def normalize(_actor), do: :none

  defp user(id) when is_binary(id) and id != "", do: {:user, id}
  defp user(_id), do: :none
  defp service(id) when is_binary(id) and id != "", do: {:service, id}
  defp service(_id), do: :none
end
