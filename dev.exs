# Development server for working on tiptapex itself.
#
#     cd dev/assets && npm install && cd ../..
#     mix dev.assets        # bundle the demo JS
#     iex -S mix dev        # then open http://localhost:4400
#
# Routes:
#   /                      — full editor demo (uploads to local disk, collab on)
#   /viewer                — server-rendered + hydrated viewer of the doc
#   /print                 — the print-ready HTML Tiptapex.Export.PDF builds
#   /print/chromic         — a real PDF via ChromicPDF (headless Chrome)
#   /print/wkhtmltopdf     — a real PDF via pdf_generator (wkhtmltopdf)
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

if path = System.find_executable("wkhtmltopdf") do
  Application.put_env(:pdf_generator, :wkhtml_path, path)
end

# ChromicPDF drives a headless Chrome, so it is only supervised when there is
# one to drive — the demo still boots (and /print/wkhtmltopdf still works) on
# a machine without Chrome.
chrome? =
  Enum.any?(
    ~w(chromium chromium-browser google-chrome google-chrome-stable),
    &System.find_executable/1
  ) or File.exists?("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

{:ok, sup} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: Tiptapex.DevPubSub},
      # Holds the last edited doc so /viewer can render it.
      %{
        id: Tiptapex.DevDoc,
        start: {Agent, :start_link, [fn -> nil end, [name: Tiptapex.DevDoc]]}
      },
      Tiptapex.DevWeb.Endpoint
    ] ++ if(chrome?, do: [ChromicPDF], else: []),
    strategy: :one_for_one
  )

unless chrome? do
  IO.puts("(no Chrome found — /print/chromic is disabled, /print/wkhtmltopdf still works)")
end

# Under `iex -S mix dev` this script's process exits as soon as the file
# finishes evaluating, and a linked supervisor (supervisors trap exits and
# shut down when their parent dies) would silently take the endpoint with
# it. Unlink so the server survives the script under both entry points.
Process.unlink(sup)

IO.puts("\n== Tiptapex dev server running at http://localhost:4400 ==\n")

unless IEx.started?() do
  Process.sleep(:infinity)
end
