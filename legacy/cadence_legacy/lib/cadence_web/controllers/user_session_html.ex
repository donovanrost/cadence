defmodule CadenceWeb.UserSessionHTML do
  use CadenceWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:cadence, Cadence.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
