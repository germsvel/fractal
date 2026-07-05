defmodule Fractal.BusTest do
  use ExUnit.Case, async: true

  alias Fractal.Bus

  test "publish/1 rings subscribers with a payload-free doorbell" do
    :ok = Bus.subscribe("bus-test/42/ticks")

    Fractal.Interactive.publish("bus-test/42/ticks")

    assert_receive {:fractal_watch, "bus-test/42/ticks"}
  end

  test "publishes reach only their own topic" do
    :ok = Bus.subscribe("bus-test/mine")

    Fractal.Interactive.publish("bus-test/theirs")

    refute_receive {:fractal_watch, _topic}, 50
  end

  test "publish/1 rejects non-concrete or malformed topics" do
    for bad <- ["rooms/:id/messages", "/rooms/1", "", "rooms//x", :not_a_string] do
      assert_raise ArgumentError, ~r/concrete, path-shaped topic/, fn ->
        Fractal.Interactive.publish(bad)
      end
    end
  end

  test "valid_topic?/1 accepts route vocabulary without a leading slash" do
    assert Bus.valid_topic?("rooms/:id/messages")
    assert Bus.valid_topic?("posts")
    refute Bus.valid_topic?("/rooms")
    refute Bus.valid_topic?("rooms/*/messages")
    refute Bus.valid_topic?("")
    refute Bus.valid_topic?(nil)
  end

  test "topic_params/1 and resolve/2 bind :name segments" do
    assert Bus.topic_params("rooms/:id/messages") == ["id"]
    assert Bus.topic_params("posts") == []

    assert Bus.resolve("rooms/:id/messages", %{"id" => "42"}) == "rooms/42/messages"
    assert Bus.resolve("posts", %{}) == "posts"
  end
end
