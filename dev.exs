# Development server for working on tiptapex itself.
#
#     cd dev/assets && npm install && cd ../..
#     mix dev.assets        # bundle the demo JS
#     iex -S mix dev        # then open http://localhost:4400
#
# Routes:
#   /        — full editor demo (uploads to local disk, collab enabled)
#   /viewer  — server-rendered + hydrated viewer of the last edited doc
#
# Open / in two browser tabs to watch realtime collaboration.

Application.put_env(:tiptapex, Tiptapex.DevWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4400],
  server: true,
  secret_key_base: String.duplicate("tiptapexdev", 6),
  live_view: [signing_salt: "ttx-dev-salt"],
  pubsub_server: Tiptapex.DevPubSub,
  debug_errors: true,
  check_origin: false
)

Application.put_env(:tiptapex, Tiptapex.Upload.LocalDisk,
  dir: "tmp/dev_uploads",
  url_prefix: "/uploads"
)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: Tiptapex.DevPubSub},
      # Holds the last edited doc so /viewer can render it.
      %{
        id: Tiptapex.DevDoc,
        start: {Agent, :start_link, [fn -> nil end, [name: Tiptapex.DevDoc]]}
      },
      Tiptapex.DevWeb.Endpoint
    ],
    strategy: :one_for_one
  )

IO.puts("\n== Tiptapex dev server running at http://localhost:4400 ==\n")

unless IEx.started?() do
  Process.sleep(:infinity)
end
