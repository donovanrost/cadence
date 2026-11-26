defmodule CadenceWeb.API.ActorDocument do
  @moduledoc """
  The REST view of a stored actor document (#466, #462). Rows written before #466 may hold a
  person's email (`email` from the activation writer, `user_email` from the REST actor
  document); they stay as they are (#116), and this drops those keys on the way out. Nothing
  else in the object changes.

  It runs only at the REST encoders, never on a domain struct, so a hash computed from the
  stored document (e.g. `RequestDigest.digest/1`) sees it unchanged.
  """

  alias Cadence.Control.ActorRef

  @email_keys ["email", "user_email", :email, :user_email]

  @doc """
  #465: what `actor/2` needs for `documents`, under `organization_id`: the organization of the
  records' mission, never a request parameter (`Control.ActorRef.names/2`, #472).
  """
  @spec names(binary() | nil, [term()]) :: ActorRef.names()
  def names(organization_id, documents),
    do: ActorRef.names(organization_id, Enum.map(documents, &public/1))

  @doc """
  #465: a stored actor document as REST shows it, `{kind, id, name}` (#146 via `ActorRef`): a
  person named and identified only while an active member of the organization, a service of the
  organization by its live name, the system actor as stored. A form Cadence can't read is `nil`
  (the whole field), never an email, never the stored keys.
  """
  @spec actor(term(), ActorRef.names()) :: ActorRef.t() | nil
  def actor(document, names), do: document |> public() |> ActorRef.document(names)

  @spec public(term()) :: term()
  def public(%{} = document) when not is_struct(document), do: Map.drop(document, @email_keys)
  def public(other), do: other
end
