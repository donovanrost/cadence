defmodule Cadence.ContactPlanning.GrantNarrowing do
  @moduledoc """
  Whether a change to an active automation grant only takes access away (#283, ux U105;
  ca-security 11-19). It's judged on the effective grant across every field a change may touch:

  - `allowed_actions`: a subset;
  - `maximum_horizon_seconds`, `maximum_contacts`, `maximum_execution_concurrency`: no larger;
  - `maximum_estimated_cost_micros`: no larger, and adding a limit where there was none narrows
    (removing one widens). Its `currency` can't change;
  - `validity_seconds`: no longer. The window stays anchored at the original approval, so it can
    only end sooner, never move.

  Any other field (the service, the mission, the policy) or an unknown key counts as widening,
  so it needs a new proposal. A change that leaves everything as it was is a no-op, not a
  narrowing (`automation_grant_narrow_unchanged`).
  """

  alias Cadence.ContactPlanning.AutomationGrant

  @limits ~w(maximum_horizon_seconds maximum_contacts maximum_execution_concurrency validity_seconds)a
  @fields [:allowed_actions, :maximum_estimated_cost_micros, :currency | @limits]

  @spec narrow(AutomationGrant.t(), map()) :: {:ok, AutomationGrant.t()} | {:error, term()}
  def narrow(%AutomationGrant{} = grant, changes) when is_map(changes) do
    with {:ok, changes} <- normalize(changes),
         [] <- widening(grant, changes),
         {:ok, narrowed} <- build(grant, changes) do
      if AutomationGrant.content_sha256(narrowed) == grant.content_sha256,
        do: {:error, :automation_grant_narrow_unchanged},
        else: {:ok, narrowed}
    else
      fields when is_list(fields) -> {:error, {:automation_grant_not_narrower, %{fields: fields}}}
      error -> error
    end
  end

  def narrow(_grant, _changes), do: {:error, {:automation_grant_not_narrower, %{fields: []}}}

  # Keys to atoms we know; anything else is kept as its string and counts as widening.
  defp normalize(changes) do
    {:ok,
     Map.new(changes, fn {key, value} ->
       {Enum.find(@fields, key, &(Atom.to_string(&1) == to_string(key))), value}
     end)}
  end

  defp widening(grant, changes) do
    changes
    |> Enum.filter(fn {field, value} -> wider?(grant, field, value) end)
    |> Enum.map(fn {field, _value} -> to_string(field) end)
    |> Enum.sort()
  end

  defp wider?(grant, :allowed_actions, actions) when is_list(actions) do
    case actions(actions) do
      {:ok, wanted} -> not MapSet.subset?(MapSet.new(wanted), MapSet.new(grant.allowed_actions))
      :error -> true
    end
  end

  defp wider?(grant, field, value) when field in @limits,
    do: not (is_integer(value) and value > 0 and value <= Map.fetch!(grant, field))

  defp wider?(%{maximum_estimated_cost_micros: nil}, :maximum_estimated_cost_micros, value),
    do: not (is_integer(value) and value >= 0)

  defp wider?(grant, :maximum_estimated_cost_micros, value),
    do: not (is_integer(value) and value >= 0 and value <= grant.maximum_estimated_cost_micros)

  defp wider?(grant, :currency, value),
    do: not (is_binary(value) and String.upcase(value) == grant.currency)

  # An unknown key, or a known one with a value of the wrong kind.
  defp wider?(_grant, _field, _value), do: true

  defp build(grant, changes) do
    changes = Map.update(changes, :allowed_actions, nil, &elem(actions(&1), 1))
    changes = Map.reject(changes, fn {_field, value} -> is_nil(value) end)

    window =
      case changes do
        %{validity_seconds: seconds} ->
          %{valid_until: DateTime.add(grant.valid_from, seconds, :second)}

        _same ->
          %{}
      end

    narrowed =
      grant
      |> Map.from_struct()
      |> Map.merge(changes)
      |> Map.merge(window)
      |> Map.put(:content_sha256, nil)
      |> AutomationGrant.new()

    {:ok, narrowed}
  rescue
    error in ArgumentError -> {:error, {:invalid_automation_grant, error.message}}
  end

  defp actions(actions) do
    known = AutomationGrant.actions()

    atoms =
      Enum.map(actions, fn action ->
        Enum.find(known, &(Atom.to_string(&1) == to_string(action)))
      end)

    if atoms != [] and Enum.all?(atoms, & &1),
      do: {:ok, Enum.sort(Enum.uniq(atoms))},
      else: :error
  end
end
