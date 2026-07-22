defmodule Tiptapex.Renderer.SecurityTest do
  use ExUnit.Case, async: true

  alias Tiptapex.Renderer
  alias Tiptapex.Renderer.URL

  defp html(doc, opts \\ []) do
    doc |> Renderer.to_html(opts) |> Phoenix.HTML.safe_to_string()
  end

  defp doc(content), do: %{"type" => "doc", "content" => List.wrap(content)}
  defp p(content), do: %{"type" => "paragraph", "content" => List.wrap(content)}

  defp link_text(text, href) do
    %{
      "type" => "text",
      "text" => text,
      "marks" => [%{"type" => "link", "attrs" => %{"href" => href}}]
    }
  end

  describe "URL scheme allow-list" do
    test "javascript: hrefs are stripped, text preserved" do
      rendered = html(doc(p(link_text("click", "javascript:alert(1)"))))
      assert rendered == "<p>click</p>"
      refute rendered =~ "javascript"
    end

    test "case and whitespace tricks don't bypass the scheme check" do
      for href <- [
            "JAVASCRIPT:alert(1)",
            "JaVaScRiPt:alert(1)",
            " javascript:alert(1) ",
            "java\nscript:alert(1)",
            "\tjavascript:alert(1)",
            "vbscript:msgbox(1)",
            "data:text/html;base64,PHNjcmlwdD4=",
            "Data:text/html,<script>alert(1)</script>"
          ] do
        rendered = html(doc(p(link_text("x", href))))
        assert rendered == "<p>x</p>", "href not stripped: #{inspect(href)}"
      end
    end

    test "image with data: URI is dropped entirely" do
      node = %{
        "type" => "image",
        "attrs" => %{"src" => "data:image/svg+xml,<svg onload=alert(1)>"}
      }

      assert html(doc(node)) == ""
    end

    test "http, https, mailto, and relative URLs pass" do
      assert {:ok, _} = URL.safe_url("https://example.com/a")
      assert {:ok, _} = URL.safe_url("http://example.com")
      assert {:ok, _} = URL.safe_url("mailto:a@b.cl")
      assert {:ok, _} = URL.safe_url("/uploads/x.png")
      assert {:ok, _} = URL.safe_url("#section")
      assert :error = URL.safe_url("javascript:x")
      assert :error = URL.safe_url("")
      assert :error = URL.safe_url(nil)
    end
  end

  describe "script and attribute injection" do
    test "script tags in text are escaped" do
      rendered = html(doc(p(%{"type" => "text", "text" => "<script>document.cookie</script>"})))
      refute rendered =~ "<script>"
      assert rendered =~ "&lt;script&gt;"
    end

    test "attribute breakout via image alt is escaped" do
      node = %{
        "type" => "image",
        "attrs" => %{"src" => "/a.png", "alt" => "\" onerror=\"alert(1)"}
      }

      # The quote characters are escaped, so the payload stays inside the
      # alt value — no attribute breakout is possible.
      assert html(doc(node)) == "<img src=\"/a.png\" alt=\"&quot; onerror=&quot;alert(1)\">"
    end

    test "event-handler attributes in node attrs are never emitted" do
      node = %{
        "type" => "image",
        "attrs" => %{"src" => "/a.png", "onerror" => "alert(1)", "onclick" => "alert(2)"}
      }

      rendered = html(doc(node))
      refute rendered =~ "onerror"
      refute rendered =~ "onclick"
    end
  end

  describe "style breakout" do
    test "style values with breakout characters are rejected" do
      for value <- [
            "16px;background:url(javascript:alert(1))",
            "red}body{display:none",
            "expression(alert(1))",
            "url(https://evil.com)",
            "16px\"><script>",
            "rgb(1,calc(2),3)"
          ] do
        mark = %{"type" => "textStyle", "attrs" => %{"fontSize" => value}}
        rendered = html(doc(p(%{"type" => "text", "text" => "x", "marks" => [mark]})))
        assert rendered == "<p>x</p>", "style not rejected: #{inspect(value)}"
      end
    end

    test "lineHeight breakout on paragraph is dropped" do
      node = %{
        "type" => "paragraph",
        "attrs" => %{"lineHeight" => "1.5;position:fixed"},
        "content" => [%{"type" => "text", "text" => "x"}]
      }

      assert html(doc(node)) == "<p>x</p>"
    end
  end

  describe "iframe restrictions" do
    test "non-YouTube iframe src drops the whole video node" do
      for src <- [
            "https://evil.com/embed/x",
            "https://youtube.com.evil.com/embed/x",
            "https://www.youtube.com@evil.com/embed/x",
            "javascript:alert(1)"
          ] do
        node = %{"type" => "video", "attrs" => %{"src" => src, "kind" => "youtube"}}
        assert html(doc(node)) == "", "iframe not dropped for #{src}"
      end
    end

    test "youtube embed is rebuilt canonically, query params discarded" do
      assert {:ok, "https://www.youtube.com/embed/dQw4w9WgXcQ"} =
               URL.youtube_embed("https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1&x=<svg>")

      assert :error = URL.youtube_embed("https://www.youtube.com/watch?v=<script>")
      assert :error = URL.youtube_embed("https://www.youtube.com/embed/../evil")
    end
  end

  describe "unknown content" do
    test "unknown node types are dropped by default" do
      assert html(doc(%{"type" => "iframe", "attrs" => %{"src" => "https://evil.com"}})) == ""
    end

    test "unknown mark types are dropped by default" do
      text = %{"type" => "text", "text" => "x", "marks" => [%{"type" => "onhover"}]}
      assert html(doc(p(text))) == "<p>x</p>"
    end
  end
end
