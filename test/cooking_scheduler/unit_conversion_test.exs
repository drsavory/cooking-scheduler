defmodule CookingScheduler.UnitConversionTest do
  use ExUnit.Case, async: true
  doctest CookingScheduler.UnitConversion

  alias CookingScheduler.UnitConversion, as: U

  test "temperatures" do
    assert U.convert(350, :f, :c, round: 1) == {:ok, 176.7}
    assert U.convert(180, :c, :f) == {:ok, 356.0}
    assert U.convert(4, :gas_mark, :c) == {:ok, 180.0}
    assert U.convert(4, "gas mark", :f, round: 0) == {:ok, 356.0}
    assert U.convert(0.5, "gas", :c) == {:ok, 130.0}
    assert U.convert(350, :f, "gas mark") == {:ok, 4.0}
    assert U.convert(200, :c, :gas_mark) == {:ok, 6.0}
    assert U.convert(100, :c, :gas_mark) == {:ok, 0.25}
    assert U.convert(50, :c, :gas_mark) == {:error, :out_of_range}
    assert U.convert(11, :gas_mark, :c) == {:error, :invalid_value}
    assert U.convert(212, "°F", "celsius") == {:ok, 100.0}
  end

  test "weights" do
    assert U.convert(1, :lb, :g, round: 1) == {:ok, 453.6}
    assert U.convert(500, :g, :kg) == {:ok, 0.5}
    assert U.convert(16, :oz, :lb, round: 6) == {:ok, 1.0}
    assert U.convert(2, "pounds", "oz", round: 6) == {:ok, 32.0}
  end

  test "volumes" do
    assert U.convert(1, :tbsp, :tsp, round: 6) == {:ok, 3.0}
    assert U.convert(1, :cup, :tbsp, round: 6) == {:ok, 16.0}
    assert U.convert(1, :cup, :ml, round: 1) == {:ok, 236.6}
    assert U.convert(1, :gallon, :quart, round: 6) == {:ok, 4.0}
    assert U.convert(1, "fl oz", "tbsp", round: 6) == {:ok, 2.0}
    assert U.convert(1, "Tablespoons.", :tsp, round: 6) == {:ok, 3.0}
  end

  test "volume to weight by ingredient" do
    assert U.convert(1, :cup, :g, ingredient: :flour, round: 0) == {:ok, 120.0}
    assert U.convert(2, "cups", "g", ingredient: "Plain Flour", round: 0) == {:ok, 240.0}
    assert U.convert(1, :tbsp, :g, ingredient: :butter, round: 1) == {:ok, 14.2}
    assert U.convert(200, :g, :cup, ingredient: :sugar, round: 2) == {:ok, 1.0}
    assert U.convert(1, :cup, :g, ingredient: :generic, round: 0) == {:ok, 237.0}
    assert U.convert(8, :oz, :cup, ingredient: :water, round: 2) == {:ok, 0.96}
  end

  test "errors" do
    assert U.convert(1, :cup, :g) == {:error, :incompatible_units}
    assert U.convert(1, :cup, :g, ingredient: :unobtainium) == {:error, :unknown_ingredient}
    assert U.convert(1, :c, :lb) == {:error, :incompatible_units}
    assert U.convert(1, "furlong", :g) == {:error, :unknown_unit}
    assert U.convert(1, nil, :g) == {:error, :unknown_unit}
    assert U.convert("1", :g, :kg) == {:error, :invalid_value}
    assert_raise ArgumentError, fn -> U.convert!(1, :cup, :g) end
  end

  test "category and units" do
    assert U.category(:tbsp) == :volume
    assert U.category(:bogus) == nil
    assert :cup in U.units(:volume)
  end
end
