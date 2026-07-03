defmodule Fractal.HTMLTest do
  use ExUnit.Case, async: true

  import Fractal.HTML

  doctest Fractal.HTML

  describe "escape/1" do
    test "escapes HTML-significant characters" do
      assert escape(~s{<script>alert("x & 'y'")</script>}) ==
               "&lt;script&gt;alert(&quot;x &amp; &#39;y&#39;&quot;)&lt;/script&gt;"
    end

    test "leaves plain text untouched" do
      assert escape("hello world") == "hello world"
    end
  end

  describe "tag/3" do
    test "renders an element with escaped text children" do
      assert render(tag(:p, [], ["1 < 2"])) == "<p>1 &lt; 2</p>"
    end

    test "renders nested elements" do
      html = tag(:div, [], [tag(:span, [], ["a"]), tag(:span, [], ["b"])])
      assert render(html) == "<div><span>a</span><span>b</span></div>"
    end

    test "escapes attribute values" do
      assert render(tag(:a, [href: ~s("/x")], ["link"])) ==
               ~s(<a href="&quot;/x&quot;">link</a>)
    end

    test "renders boolean and nil attributes" do
      assert render(tag(:input, required: true, disabled: false, value: nil)) ==
               "<input required>"
    end

    test "converts underscores in attribute names to dashes" do
      assert render(tag(:div, [aria_label: "Close"], [])) == ~s(<div aria-label="Close"></div>)
    end

    test "renders void elements without a closing tag" do
      assert render(tag(:br)) == "<br>"
      assert render(tag(:img, src: "/x.png")) == ~s(<img src="/x.png">)
    end

    test "accepts numbers, nil, and mixed lists as children" do
      assert render(tag(:p, [], ["n = ", 42, nil])) == "<p>n = 42</p>"
    end
  end

  describe "raw/1" do
    test "passes content through unescaped" do
      assert render(tag(:div, [], [raw("<b>bold</b>")])) == "<div><b>bold</b></div>"
    end
  end

  describe "to_safe/1" do
    test "escapes plain strings" do
      assert render(to_safe("<b>")) == "&lt;b&gt;"
    end

    test "passes safe content through" do
      safe = tag(:p, [], ["hi"])
      assert to_safe(safe) == safe
    end

    test "handles lists of mixed content" do
      assert render(to_safe(["a < b", tag(:br)])) == "a &lt; b<br>"
    end
  end

  defp render(safe), do: safe_to_string(to_safe(safe))
end
