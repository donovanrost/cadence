defmodule CadenceWeb.ActivationParams do
  @moduledoc false

  import CadenceWeb.ControlPlaneParams.Parser

  @change_classes [
    :observational,
    :mission_data_plane,
    :transport_provider,
    :command_safety,
    :identity_policy
  ]

  @spec request(map()) :: {:ok, map()} | {:error, term()}
  def request(params) when is_map(params) do
    with {:ok, binding_set_id} <- required_string(params, "binding_set_id"),
         {:ok, version} <- positive_integer(params, "version", nil),
         {:ok, change_class} <-
           allowed_atom_param(
             params,
             "change_class",
             :mission_data_plane,
             @change_classes
           ),
         {:ok, metadata} <- optional_map(params, "metadata", %{}) do
      {:ok,
       %{
         binding_set_id: binding_set_id,
         version: version,
         change_class: change_class,
         metadata: metadata
       }}
    end
  end

  @spec decision(map()) :: {:ok, binary()} | {:error, term()}
  def decision(params) when is_map(params), do: required_string(params, "reason")

  @spec filters(map()) :: {:ok, keyword()} | {:error, term()}
  def filters(params) when is_map(params) do
    with {:ok, state} <-
           optional_allowed_atom_param(
             params,
             "state",
             [:approval_pending, :approved, :rejected]
           ),
         {:ok, limit} <- optional_positive_integer(params, "limit") do
      {:ok,
       []
       |> maybe_put(:state, state)
       |> maybe_put(:binding_set_id, string_value(params, "binding_set_id"))
       |> maybe_put(:limit, limit)}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
