defmodule Tiptapex.Upload.Controller do
  @moduledoc """
  Drop-in controller action for editor uploads.

      defmodule MyAppWeb.EditorUploadController do
        use MyAppWeb, :controller

        use Tiptapex.Upload.Controller,
          handler: MyApp.EditorUploads,
          max_bytes: 25_000_000,
          allowed: ~w(image/png image/jpeg image/gif image/webp video/mp4 video/webm application/pdf),
          scope_param: "scope"
      end

  Then mount it inside an authenticated pipeline:

      scope "/admin", MyAppWeb do
        pipe_through [:browser, :require_authenticated_user]
        post "/tiptapex/uploads", EditorUploadController, :create
      end

  The injected `create/2`:

    1. requires a `"file"` multipart part;
    2. validates it with `Tiptapex.Upload.Validator` (size + magic-byte
       content-type verification);
    3. builds the context via `build_context/2` (overridable — default:
       `%{scope: params[scope_param], params: params, conn_assigns:
       conn.assigns}`);
    4. calls `handler.store/2` (your `Tiptapex.Upload` implementation);
    5. replies with the JSON contract the JS hook expects
       (`{"url", "content_type", "filename"}`) or a 422 with an error code.

  CSRF: the JS hook sends the `x-csrf-token` header, which the standard
  `:browser` pipeline (`protect_from_forgery`) validates — no extra
  plumbing needed. Keep the route out of `:api`-style pipelines that skip
  CSRF unless you add your own protection.
  """

  import Plug.Conn

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @tiptapex_upload_config %{
        handler: Keyword.fetch!(opts, :handler),
        max_bytes: Keyword.get(opts, :max_bytes, Tiptapex.Upload.Validator.default_max_bytes()),
        allowed: Keyword.get(opts, :allowed, Tiptapex.Upload.Validator.default_allowed()),
        scope_param: Keyword.get(opts, :scope_param, "scope")
      }

      def create(conn, params) do
        Tiptapex.Upload.Controller.handle_create(
          conn,
          params,
          @tiptapex_upload_config,
          &build_context/2
        )
      end

      def build_context(conn, params) do
        %{
          scope: Map.get(params, @tiptapex_upload_config.scope_param),
          params: params,
          conn_assigns: conn.assigns
        }
      end

      defoverridable create: 2, build_context: 2
    end
  end

  @doc false
  def handle_create(conn, params, config, build_context) do
    with {:ok, upload} <- fetch_upload(params),
         {:ok, meta} <-
           Tiptapex.Upload.Validator.validate(upload,
             max_bytes: config.max_bytes,
             allowed: config.allowed
           ),
         {:ok, result} <- config.handler.store(upload, build_context.(conn, params)) do
      send_json(conn, 200, %{
        url: result.url,
        content_type: Map.get(result, :content_type) || meta.content_type,
        filename: Map.get(result, :filename) || meta.filename
      })
    else
      {:error, reason} -> send_json(conn, 422, %{error: error_code(reason)})
    end
  end

  defp fetch_upload(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp fetch_upload(_params), do: {:error, :missing_file}

  defp error_code(reason) when is_atom(reason), do: to_string(reason)
  defp error_code(_reason), do: "store_failed"

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
