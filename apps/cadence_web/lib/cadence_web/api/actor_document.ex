defmodule CadenceWeb.API.ActorDocument do
  @moduledoc """
  The REST view of a stored actor document (#466, #462). Rows written before #466 may hold a
  person's email (`email` from the activation writer, `user_email` from the REST actor
  document); they stay as they are (#116), and this drops those keys on the way out. Nothing
  else in the object changes.

  It runs only at the REST encoders, never on a domain struct, so a hash computed from the
  stored document (e.g. `ReviewPrecondition.digest/1`) sees it unchanged.
  """

  @email_keys ["email", "user_email", :email, :user_email]

  @spec public(term()) :: term()
  def public(%{} = document) when not is_struct(document), do: Map.drop(document, @email_keys)
  def public(other), do: other
end
