defmodule CadenceWeb.ActivationParams do
  @moduledoc false

  import CadenceWeb.API.ParamParser

  # Metadata keys the server builds during admission (DECISIONS #32); a client can't set them.
  @reserved_metadata_keys ~w(spacecraft_configuration_version spacecraft_configurations fleet
                             configuration_review mission_model)

  @spec request(map()) :: {:ok, map()} | {:error, term()}
  def request(params) when is_map(params) do
    with {:ok, mission_model_revision_id} <-
           required_string(params, "mission_model_revision_id"),
         {:ok, binding_set_id} <- required_string(params, "binding_set_id"),
         {:ok, version} <- positive_integer(params, "version", nil),
         {:ok, metadata} <- optional_map(params, "metadata", %{}),
         :ok <- unreserved(metadata) do
      {:ok,
       %{
         mission_model_revision_id: mission_model_revision_id,
         binding_set_id: binding_set_id,
         version: version,
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

  defp unreserved(metadata) when is_map(metadata) do
    if Enum.any?(Map.keys(metadata), &(to_string(&1) in @reserved_metadata_keys)),
      do: {:error, {:invalid_param, "metadata", :reserved_metadata_key}},
      else: :ok
  end

  defp unreserved(_metadata), do: :ok

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
