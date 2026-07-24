defmodule Tiptapex.RendererTest do
  use ExUnit.Case, async: true

  alias Tiptapex.Renderer

  defp html(doc, opts \\ []) do
    doc |> Renderer.to_html(opts) |> Phoenix.HTML.safe_to_string()
  end

  defp doc(content), do: %{"type" => "doc", "content" => List.wrap(content)}
  defp p(content), do: %{"type" => "paragraph", "content" => List.wrap(content)}
  defp text(t), do: %{"type" => "text", "text" => t}
  defp text(t, marks), do: %{"type" => "text", "text" => t, "marks" => List.wrap(marks)}

  describe "to_html/2 basics" do
    test "nil and empty docs render to empty safe HTML" do
      assert Renderer.to_html(nil) == {:safe, ""}
      assert Renderer.to_html(%{}) == {:safe, ""}
    end

    test "paragraph with text" do
      assert html(doc(p(text("Hello")))) == "<p>Hello</p>"
    end

    test "escapes text content" do
      assert html(doc(p(text("<script>alert(1)</script>")))) ==
               "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>"
    end

    test "accepts atom-keyed documents" do
      atom_doc = %{
        type: "doc",
        content: [%{type: "paragraph", content: [%{type: "text", text: "hi"}]}]
      }

      assert html(atom_doc) == "<p>hi</p>"
    end

    test "empty paragraph renders" do
      assert html(doc(%{"type" => "paragraph"})) == "<p></p>"
    end
  end

  describe "block nodes" do
    test "heading with valid id and level" do
      node = %{
        "type" => "heading",
        "attrs" => %{"level" => 2, "id" => "abc-123"},
        "content" => [text("Section")]
      }

      assert html(doc(node)) == "<h2 id=\"abc-123\">Section</h2>"
    end

    test "ids: false omits heading ids (live-preview mode)" do
      node = %{
        "type" => "heading",
        "attrs" => %{"level" => 2, "id" => "abc-123"},
        "content" => [text("Section")]
      }

      assert html(doc(node), ids: false) == "<h2>Section</h2>"
    end

    test "heading clamps invalid level and drops unsafe id" do
      node = %{
        "type" => "heading",
        "attrs" => %{"level" => 99, "id" => "\"><script>"},
        "content" => [text("X")]
      }

      assert html(doc(node)) == "<h1>X</h1>"
    end

    test "paragraph textAlign and lineHeight become style" do
      node = %{
        "type" => "paragraph",
        "attrs" => %{"textAlign" => "right", "lineHeight" => "1.5"},
        "content" => [text("x")]
      }

      assert html(doc(node)) == "<p style=\"text-align: right; line-height: 1.5\">x</p>"
    end

    test "invalid textAlign is dropped" do
      node = %{
        "type" => "paragraph",
        "attrs" => %{"textAlign" => "evil;}"},
        "content" => [text("x")]
      }

      assert html(doc(node)) == "<p>x</p>"
    end

    test "codeBlock with language class" do
      node = %{
        "type" => "codeBlock",
        "attrs" => %{"language" => "elixir"},
        "content" => [text("IO.puts(1)")]
      }

      assert html(doc(node)) == "<pre><code class=\"language-elixir\">IO.puts(1)</code></pre>"
    end

    test "codeBlock with malicious language drops the class" do
      node = %{
        "type" => "codeBlock",
        "attrs" => %{"language" => "\"><img src=x>"},
        "content" => [text("x")]
      }

      assert html(doc(node)) == "<pre><code>x</code></pre>"
    end

    test "ordered list start" do
      node = %{
        "type" => "orderedList",
        "attrs" => %{"start" => 3},
        "content" => [%{"type" => "listItem", "content" => [p(text("a"))]}]
      }

      assert html(doc(node)) == "<ol start=\"3\"><li><p>a</p></li></ol>"
    end

    test "task list with checked and unchecked items" do
      node = %{
        "type" => "taskList",
        "content" => [
          %{"type" => "taskItem", "attrs" => %{"checked" => true}, "content" => [p(text("a"))]},
          %{"type" => "taskItem", "attrs" => %{"checked" => false}, "content" => [p(text("b"))]}
        ]
      }

      assert html(doc(node)) ==
               "<ul data-type=\"taskList\">" <>
                 "<li data-type=\"taskItem\" data-checked=\"true\"><label><input type=\"checkbox\" disabled checked><span></span></label><div><p>a</p></div></li>" <>
                 "<li data-type=\"taskItem\" data-checked=\"false\"><label><input type=\"checkbox\" disabled><span></span></label><div><p>b</p></div></li>" <>
                 "</ul>"
    end

    test "table cells with colspan, rowspan, and colwidth" do
      node = %{
        "type" => "table",
        "content" => [
          %{
            "type" => "tableRow",
            "content" => [
              %{
                "type" => "tableCell",
                "attrs" => %{"colspan" => 2, "rowspan" => 3, "colwidth" => [100, 200]},
                "content" => [p(text("c"))]
              }
            ]
          }
        ]
      }

      assert html(doc(node)) ==
               "<table><tbody><tr>" <>
                 "<td colspan=\"2\" rowspan=\"3\" data-colwidth=\"100,200\"><p>c</p></td>" <>
                 "</tr></tbody></table>"
    end

    test "horizontal rule and hard break" do
      assert html(doc(%{"type" => "horizontalRule"})) == "<hr>"
      assert html(doc(p(%{"type" => "hardBreak"}))) == "<p><br></p>"
    end

    test "page break carries the CSS break inline so it works without a stylesheet" do
      assert html(doc(%{"type" => "pageBreak"})) ==
               ~s(<div data-page-break="true" class="ttx-page-break" ) <>
                 ~s(style="break-after: page; page-break-after: always;"></div>)
    end

    test "page breaks are not content — a document of breaks is still blank" do
      assert Tiptapex.blank_doc?(doc(%{"type" => "pageBreak"}))
      assert Tiptapex.Renderer.to_plain_text(doc(%{"type" => "pageBreak"})) == ""
    end
  end

  describe "media nodes" do
    test "image with width" do
      node = %{
        "type" => "image",
        "attrs" => %{"src" => "/up/a.png", "alt" => "A", "width" => 300}
      }

      assert html(doc(node)) ==
               "<img src=\"/up/a.png\" alt=\"A\" width=\"300\" style=\"width: 300px; height: auto;\">"
    end

    test "image without width has no style" do
      node = %{"type" => "image", "attrs" => %{"src" => "https://cdn.example.com/a.png"}}
      assert html(doc(node)) == "<img src=\"https://cdn.example.com/a.png\">"
    end

    test "file video" do
      node = %{
        "type" => "video",
        "attrs" => %{"src" => "/up/v.mp4", "kind" => "file", "title" => "demo", "width" => 400}
      }

      assert html(doc(node)) ==
               "<div data-video=\"file\" class=\"ttx-video ttx-video-file\" style=\"width: 400px;\">" <>
                 "<video src=\"/up/v.mp4\" controls=\"true\" playsinline=\"true\" title=\"demo\" preload=\"metadata\"></video></div>"
    end

    test "youtube video normalizes watch URLs to canonical embed" do
      for url <- [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ"
          ] do
        node = %{"type" => "video", "attrs" => %{"src" => url, "kind" => "youtube"}}
        rendered = html(doc(node))

        assert rendered =~ "src=\"https://www.youtube.com/embed/dQw4w9WgXcQ\"",
               "failed for #{url}"

        assert rendered =~ "data-video=\"youtube\""
      end
    end
  end

  describe "marks" do
    test "nested marks in deterministic order" do
      assert html(doc(p(text("x", [%{"type" => "bold"}, %{"type" => "italic"}])))) ==
               "<p><em><strong>x</strong></em></p>"

      # Same output regardless of input mark order.
      assert html(doc(p(text("x", [%{"type" => "italic"}, %{"type" => "bold"}])))) ==
               "<p><em><strong>x</strong></em></p>"
    end

    test "link mark with target and forced rel" do
      mark = %{"type" => "link", "attrs" => %{"href" => "https://x.dev", "target" => "_blank"}}

      assert html(doc(p(text("go", mark)))) ==
               "<p><a href=\"https://x.dev\" target=\"_blank\" rel=\"noopener nofollow\">go</a></p>"
    end

    test "link with disallowed target drops target only" do
      mark = %{"type" => "link", "attrs" => %{"href" => "/x", "target" => "evil"}}

      assert html(doc(p(text("go", mark)))) ==
               "<p><a href=\"/x\" rel=\"noopener nofollow\">go</a></p>"
    end

    test "textStyle combines sanitized styles" do
      mark = %{
        "type" => "textStyle",
        "attrs" => %{
          "color" => "#dc2626",
          "backgroundColor" => "#fef3c7",
          "fontSize" => "18px",
          "fontFamily" => "Georgia, serif"
        }
      }

      assert html(doc(p(text("x", mark)))) ==
               "<p><span style=\"color: #dc2626; background-color: #fef3c7; font-size: 18px; font-family: Georgia, serif\">x</span></p>"
    end

    test "textStyle with no valid attrs passes children through" do
      mark = %{"type" => "textStyle", "attrs" => %{"color" => "red;}<script>"}}
      assert html(doc(p(text("x", mark)))) == "<p>x</p>"
    end

    test "highlight mark" do
      mark = %{"type" => "highlight", "attrs" => %{"color" => "#fef3c7"}}

      assert html(doc(p(text("x", mark)))) ==
               "<p><mark data-color=\"#fef3c7\" style=\"background-color: #fef3c7\">x</mark></p>"
    end

    test "functional color notation is accepted" do
      mark = %{"type" => "textStyle", "attrs" => %{"color" => "hsl(220, 70%, 55%)"}}

      assert html(doc(p(text("x", mark)))) ==
               "<p><span style=\"color: hsl(220, 70%, 55%)\">x</span></p>"
    end
  end

  describe "unknown types and extensibility" do
    test "unknown nodes are dropped by default" do
      assert html(doc(%{"type" => "widget", "content" => [p(text("x"))]})) == ""
    end

    test "on_unknown: :keep_children" do
      assert html(doc(%{"type" => "widget", "content" => [p(text("x"))]}),
               on_unknown: :keep_children
             ) == "<p>x</p>"
    end

    test "on_unknown: :raise" do
      assert_raise ArgumentError, ~r/unknown Tiptap node type/, fn ->
        html(doc(%{"type" => "widget"}), on_unknown: :raise)
      end
    end

    test "custom node renderer via :nodes" do
      callout = fn _node, children, _opts ->
        Tiptapex.Renderer.HTML.tag("aside", [{"class", "callout"}], children)
      end

      assert html(doc(%{"type" => "callout", "content" => [p(text("hi"))]}),
               nodes: %{"callout" => callout}
             ) == "<aside class=\"callout\"><p>hi</p></aside>"
    end

    test "custom mark renderer via :marks" do
      kbd = fn _mark, children, _opts -> Tiptapex.Renderer.HTML.tag("kbd", [], children) end

      assert html(doc(p(text("x", %{"type" => "kbd"}))), marks: %{"kbd" => kbd}) ==
               "<p><kbd>x</kbd></p>"
    end
  end

  describe "kitchen sink golden file" do
    test "matches the expected HTML byte for byte" do
      json = File.read!(Path.join(__DIR__, "../support/fixtures/kitchen_sink.json"))
      expected = File.read!(Path.join(__DIR__, "../support/fixtures/kitchen_sink.html"))

      rendered = json |> Jason.decode!() |> html()
      assert rendered == String.replace(expected, "\n", "")
    end
  end

  describe "to_plain_text/1" do
    test "extracts block-separated text" do
      d =
        doc([
          %{"type" => "heading", "attrs" => %{"level" => 1}, "content" => [text("Title")]},
          p([text("Hello "), text("world", %{"type" => "bold"})]),
          %{
            "type" => "bulletList",
            "content" => [%{"type" => "listItem", "content" => [p(text("item"))]}]
          }
        ])

      assert Renderer.to_plain_text(d) == "Title\nHello world\nitem"
    end

    test "nil and empty" do
      assert Renderer.to_plain_text(nil) == ""
      assert Renderer.to_plain_text(Tiptapex.empty_doc()) == ""
    end
  end

  describe "headings/1" do
    test "collects levels, ids, and text in document order" do
      d =
        doc([
          %{
            "type" => "heading",
            "attrs" => %{"level" => 1, "id" => "a"},
            "content" => [text("One")]
          },
          p(text("body")),
          %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [text("Two")]}
        ])

      assert Renderer.headings(d) == [
               %{level: 1, id: "a", text: "One"},
               %{level: 2, id: nil, text: "Two"}
             ]
    end
  end

  describe "Tiptapex doc helpers" do
    test "empty_doc/0 and blank_doc?/1" do
      assert Tiptapex.blank_doc?(nil)
      assert Tiptapex.blank_doc?(%{})
      assert Tiptapex.blank_doc?(Tiptapex.empty_doc())
      refute Tiptapex.blank_doc?(doc(p(text("hi"))))
      refute Tiptapex.blank_doc?(doc(%{"type" => "image", "attrs" => %{"src" => "/a.png"}}))
    end
  end
end
