defmodule CookingScheduler.DurationTest do
  use ExUnit.Case, async: true
  alias CookingScheduler.Duration

  test "parses the ways people write times" do
    for {text, mins} <- [
          {"1:50", 110},
          {"1h50", 110},
          {"1h 50m", 110},
          {"2h", 120},
          {"2 hours", 120},
          {"45m", 45},
          {"45 min", 45},
          {"90", 90},
          {" 6:00 ", 360}
        ] do
      assert Duration.parse(text) == {:ok, mins}, text
    end
  end

  test "rejects nonsense" do
    assert Duration.parse("soon") == :error
    assert Duration.parse("-5") == :error
    assert {:error, _} = Duration.cast("abc")
  end

  test "formats and clock" do
    assert Duration.format(110) == "1h 50m"
    assert Duration.format(120) == "2h"
    assert Duration.format(45) == "45m"
    assert Duration.clock(810) == "13:30"
    assert Duration.clock(-30) == "23:30 (day before)"
  end
end
