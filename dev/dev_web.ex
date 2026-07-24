defmodule Tiptapex.DevWeb.Layouts do
  @moduledoc false
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Tiptapex Dev</title>
        <link rel="stylesheet" href="/tiptapex.css" />
        <style>
          body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 0; background: #f8fafc; color: #1f2937; }
          .dev-shell { max-width: 60rem; margin: 0 auto; padding: 2rem 1rem 4rem; }
          .dev-nav { display: flex; gap: 1rem; margin-bottom: 1.5rem; font-size: 0.9rem; }
          .dev-nav a { color: #2563eb; text-decoration: none; font-weight: 600; }
          .dev-panel { background: #fff; border: 1px solid #e5e7eb; border-radius: 0.75rem; margin-bottom: 2rem; }
          .dev-panel-title { padding: 0.75rem 1rem; border-bottom: 1px solid #e5e7eb; font-weight: 700; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; color: #6b7280; }
          .dev-panel-body { padding: 1rem; }
        </style>
        <script defer src="/dev/app.js">
        </script>
      </head>
      <body>
        <div class="dev-shell">
          <nav class="dev-nav">
            <a href="/">Editor demo</a>
            <a href="/viewer">Viewer demo</a>
            <a href="/print" target="_blank">Print HTML</a>
            <a href="/print/chromic" target="_blank">PDF · ChromicPDF</a>
            <a href="/print/wkhtmltopdf" target="_blank">PDF · wkhtmltopdf</a>
          </nav>
          {@inner_content}
        </div>
      </body>
    </html>
    """
  end
end

defmodule Tiptapex.DevWeb.UploadController do
  @moduledoc false
  use Phoenix.Controller, formats: []

  use Tiptapex.Upload.Controller,
    handler: Tiptapex.Upload.LocalDisk,
    allowed:
      ~w(image/png image/jpeg image/gif image/webp video/mp4 video/webm application/pdf text/plain)
end

defmodule Tiptapex.DevWeb.PrintController do
  @moduledoc false
  use Phoenix.Controller, formats: []

  alias Tiptapex.Export.PDF

  # The print-ready HTML, served raw so the browser's own print preview shows
  # the paginated result.
  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, PDF.to_html(doc()))
  end

  # A real PDF through headless Chrome.
  def chromic(conn, _params) do
    {source, opts} = PDF.chromic_pdf(doc(), asset_url: absolutise(conn))

    case ChromicPDF.print_to_pdf(source, opts) do
      {:ok, base64} -> send_pdf(conn, Base.decode64!(base64), "tiptapex-chromic.pdf")
      {:error, reason} -> failed(conn, "ChromicPDF", reason)
    end
  rescue
    # ChromicPDF is only supervised when a Chrome was found at boot.
    error -> failed(conn, "ChromicPDF", error)
  end

  # A real PDF through wkhtmltopdf. with_pdf_generator/3 writes the
  # --header-html / --footer-html files a logo or markup needs, and removes
  # them afterwards.
  def wkhtmltopdf(conn, _params) do
    result =
      PDF.with_pdf_generator(doc(), [], fn html, opts ->
        PdfGenerator.generate_binary(html, opts)
      end)

    case result do
      {:ok, binary} -> send_pdf(conn, binary, "tiptapex-wkhtmltopdf.pdf")
      {:error, reason} -> failed(conn, "wkhtmltopdf", reason)
    end
  rescue
    error -> failed(conn, "wkhtmltopdf", error)
  end

  defp doc, do: Agent.get(Tiptapex.DevDoc, & &1) || Tiptapex.DevWeb.EditorDemoLive.sample_doc()

  # Chrome renders the running header with no base URL, so an uploaded logo's
  # relative src would not load. This is what :asset_url is for.
  defp absolutise(conn) do
    base = "#{conn.scheme}://#{conn.host}:#{conn.port}"

    fn
      "/" <> _ = src -> base <> src
      src -> src
    end
  end

  defp send_pdf(conn, binary, filename) do
    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
    |> send_resp(200, binary)
  end

  defp failed(conn, engine, reason) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(500, "#{engine} could not render the PDF:\n\n#{inspect(reason, pretty: true)}")
  end
end

defmodule Tiptapex.DevWeb.DocChannel do
  @moduledoc false
  use Tiptapex.Collab.Channel

  @impl true
  def authorize("doc:" <> _id, _params, socket), do: {:ok, socket}
end

defmodule Tiptapex.DevWeb.UserSocket do
  @moduledoc false
  use Phoenix.Socket

  channel "doc:*", Tiptapex.DevWeb.DocChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

defmodule Tiptapex.DevWeb.Router do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {Tiptapex.DevWeb.Layouts, :root}
  end

  scope "/" do
    pipe_through :browser

    live "/", Tiptapex.DevWeb.EditorDemoLive
    live "/viewer", Tiptapex.DevWeb.ViewerDemoLive
    get "/print", Tiptapex.DevWeb.PrintController, :show
    get "/print/chromic", Tiptapex.DevWeb.PrintController, :chromic
    get "/print/wkhtmltopdf", Tiptapex.DevWeb.PrintController, :wkhtmltopdf
    post "/uploads", Tiptapex.DevWeb.UploadController, :create
  end
end

defmodule Tiptapex.DevWeb.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :tiptapex

  @session_options [
    store: :cookie,
    key: "_tiptapex_dev",
    signing_salt: "ttx-dev-session",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
  socket "/socket", Tiptapex.DevWeb.UserSocket, websocket: true

  # The library's own static files (dev bundle + stylesheet).
  plug Plug.Static, at: "/", from: {:tiptapex, "priv/static"}, gzip: false
  # Files uploaded through the LocalDisk handler.
  plug Plug.Static, at: "/uploads", from: "tmp/dev_uploads", gzip: false

  plug Plug.Session, @session_options
  plug Plug.RequestId

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Tiptapex.DevWeb.Router
end
