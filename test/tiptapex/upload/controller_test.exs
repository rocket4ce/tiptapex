defmodule Tiptapex.Upload.ControllerTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 2]

  @png_header <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0::size(64)>>

  defmodule TestHandler do
    @behaviour Tiptapex.Upload

    @impl true
    def store(upload, context) do
      send(self(), {:stored, upload.filename, context})
      {:ok, %{url: "/u/stored.png", content_type: "image/png", filename: "stored.png"}}
    end
  end

  defmodule FailingHandler do
    @behaviour Tiptapex.Upload

    @impl true
    def store(_upload, _context), do: {:error, :storage_down}
  end

  defmodule TestController do
    use Tiptapex.Upload.Controller,
      handler: TestHandler,
      max_bytes: 1_000,
      allowed: ~w(image/png)
  end

  defmodule FailingController do
    use Tiptapex.Upload.Controller, handler: FailingHandler
  end

  defmodule CustomContextController do
    use Tiptapex.Upload.Controller, handler: TestHandler

    def build_context(_conn, params) do
      %{scope: {:article, params["article_id"]}, params: params, conn_assigns: %{}}
    end
  end

  defp png_upload(tmp_dir) do
    path = Path.join(tmp_dir, "u-#{System.unique_integer([:positive])}.png")
    File.write!(path, @png_header)
    %Plug.Upload{path: path, filename: "pic.png", content_type: "image/png"}
  end

  defp json_response(conn, status) do
    assert conn.status == status
    assert conn.resp_body
    Jason.decode!(conn.resp_body)
  end

  @tag :tmp_dir
  test "successful upload returns the wire contract and builds the context", %{tmp_dir: tmp} do
    conn = conn(:post, "/uploads")
    params = %{"file" => png_upload(tmp), "scope" => "42"}

    conn = TestController.create(conn, params)

    assert %{
             "url" => "/u/stored.png",
             "content_type" => "image/png",
             "filename" => "stored.png"
           } = json_response(conn, 200)

    assert_received {:stored, "pic.png", %{scope: "42", params: %{"scope" => "42"}}}
  end

  test "missing file returns 422 missing_file" do
    conn = TestController.create(conn(:post, "/uploads"), %{})
    assert %{"error" => "missing_file"} = json_response(conn, 422)
  end

  @tag :tmp_dir
  test "validation failures return 422 with the reason", %{tmp_dir: tmp} do
    path = Path.join(tmp, "fake.png")
    File.write!(path, "not a png")
    fake = %Plug.Upload{path: path, filename: "fake.png", content_type: "image/png"}

    conn = TestController.create(conn(:post, "/uploads"), %{"file" => fake})
    assert %{"error" => "content_type_mismatch"} = json_response(conn, 422)
  end

  @tag :tmp_dir
  test "oversize upload is rejected before reaching the handler", %{tmp_dir: tmp} do
    path = Path.join(tmp, "big.png")
    File.write!(path, @png_header <> :binary.copy(<<0>>, 2_000))
    big = %Plug.Upload{path: path, filename: "big.png", content_type: "image/png"}

    conn = TestController.create(conn(:post, "/uploads"), %{"file" => big})
    assert %{"error" => "too_large"} = json_response(conn, 422)
    refute_received {:stored, _, _}
  end

  @tag :tmp_dir
  test "handler errors surface as 422", %{tmp_dir: tmp} do
    conn = FailingController.create(conn(:post, "/uploads"), %{"file" => png_upload(tmp)})
    assert %{"error" => "storage_down"} = json_response(conn, 422)
  end

  @tag :tmp_dir
  test "build_context/2 is overridable", %{tmp_dir: tmp} do
    params = %{"file" => png_upload(tmp), "article_id" => "7"}
    CustomContextController.create(conn(:post, "/uploads"), params)
    assert_received {:stored, "pic.png", %{scope: {:article, "7"}}}
  end
end
