defmodule Tiptapex.Renderer.MarkupTest do
  use ExUnit.Case, async: true

  alias Tiptapex.Renderer.Markup

  doctest Tiptapex.Renderer.Markup

  defp html(text), do: text |> Markup.to_html() |> IO.iodata_to_binary()

  describe "allowed markup" do
    test "renders inline and block tags" do
      assert html("<b>a</b><i>b</i><span>c</span>") == "<b>a</b><i>b</i><span>c</span>"
      assert html("<h1>hola</h1>") == "<h1>hola</h1>"
      assert html("<p>one</p><div>two</div>") == "<p>one</p><div>two</div>"
    end

    test "renders void tags, with or without the slash" do
      assert html("a<br>b") == "a<br>b"
      assert html("a<br/>b") == "a<br>b"
    end

    test "nests" do
      assert html("<b>bold <i>and italic</i></b>") == "<b>bold <i>and italic</i></b>"
    end

    test "leaves plain text and tokens alone" do
      assert html("Page {page} of {pages}") == "Page {page} of {pages}"
    end

    test "escapes text around the markup" do
      assert html("<b>a & b</b>") == "<b>a &amp; b</b>"
    end
  end

  describe "everything else becomes text" do
    test "unknown tags are escaped, not dropped — the author sees what happened" do
      assert html("<script>alert(1)</script>") == "&lt;script&gt;alert(1)&lt;/script&gt;"
      assert html("<iframe src=x>") == "&lt;iframe src=x&gt;"
      assert html("<marquee>hi</marquee>") == "&lt;marquee&gt;hi&lt;/marquee&gt;"
    end

    test "unquoted or malformed attributes make the whole tag text" do
      # The opener is malformed so it shows as text; the closer is well-formed
      # but has nothing open to close, so it is dropped.
      assert html("<b onclick=alert(1)>x</b>") == "&lt;b onclick=alert(1)&gt;x"
      assert html("<b ") == "&lt;b "
      assert html("a < b") == "a &lt; b"
    end

    test "an event handler on an allowed tag is dropped, the tag survives" do
      assert html(~s|<b onclick="alert(1)">x</b>|) == "<b>x</b>"

      assert html(~s|<span onmouseover="x" style="color: red">y</span>|) ==
               ~s|<span style="color: red">y</span>|
    end

    test "a comment or doctype is text" do
      assert html("<!-- hi -->") == "&lt;!-- hi --&gt;"
    end
  end

  describe "attributes" do
    test "style keeps allow-listed properties and drops the rest" do
      assert html(~s|<span style="color: #ff0000; font-weight: bold">x</span>|) ==
               ~s|<span style="color: #ff0000; font-weight: bold">x</span>|

      assert html(~s|<span style="position: fixed; color: red">x</span>|) ==
               ~s|<span style="color: red">x</span>|
    end

    test "a style value that fails the CSS grammar is dropped" do
      assert html(~s|<span style="background-color: url(javascript:alert(1))">x</span>|) ==
               "<span>x</span>"

      assert html(~s|<span style="color: expression(alert(1))">x</span>|) == "<span>x</span>"
    end

    test "links are validated and get rel" do
      assert html(~s|<a href="https://acme.test">x</a>|) ==
               ~s|<a href="https://acme.test" rel="noopener nofollow">x</a>|

      assert html(~s|<a href="/docs">x</a>|) ==
               ~s|<a href="/docs" rel="noopener nofollow">x</a>|
    end

    test "a javascript: href is dropped, leaving an inert anchor" do
      assert html(~s|<a href="javascript:alert(1)">x</a>|) == "<a>x</a>"
    end

    test "images take http(s), relative and data: image sources" do
      assert html(~s|<img src="/logo.png" alt="L" height="20">|) ==
               ~s|<img src="/logo.png" alt="L" height="20">|

      assert html(~s|<img src="data:image/png;base64,iVBOR">|) ==
               ~s|<img src="data:image/png;base64,iVBOR">|

      assert html(~s|<img src="data:text/html;base64,PHN2">|) == "<img>"
      assert html(~s|<img src="javascript:alert(1)">|) == "<img>"
    end

    test "attribute values are escaped on the way out" do
      assert html(~s|<b title="a &quot; b">x</b>|) =~ "title="
      refute html(~s|<img alt="x" src="/a.png">|) =~ "onerror"
    end
  end

  describe "malformed nesting" do
    test "unclosed tags are closed at the end" do
      assert html("<b>bold") == "<b>bold</b>"
      assert html("<b><i>x") == "<b><i>x</i></b>"
    end

    test "a stray closing tag is dropped" do
      assert html("x</b>") == "x"
      assert html("<b>x</i></b>") == "<b>x</b>"
    end
  end

  describe "markup?/1" do
    test "distinguishes markup from text that merely contains angle brackets" do
      assert Markup.markup?("<b>x</b>")
      assert Markup.markup?("a<br>b")
      refute Markup.markup?("plain")
      refute Markup.markup?("a < b")
      refute Markup.markup?("<script>x</script>"), "not renderable, so not markup"
      refute Markup.markup?(nil)
    end
  end

  test "to_html/1 tolerates non-binaries" do
    assert Markup.to_html(nil) == ""
    assert Markup.to_html(42) == ""
  end
end
