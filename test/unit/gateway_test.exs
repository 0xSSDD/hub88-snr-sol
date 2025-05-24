defmodule Challenge.GatewayTest do
  use ExUnit.Case, async: true

  alias Challenge.Gateway

  test "extracts signature from map headers" do
    headers = %{"x-hub88-signature" => "sig123"}
    assert Gateway.extract_signature(headers) == "sig123"
  end

  test "extracts signature from list headers" do
    headers = [{"x-hub88-signature", "sig456"}]
    assert Gateway.extract_signature(headers) == "sig456"
  end

  test "extracts signature case-insensitively" do
    headers = %{"X-Hub88-Signature" => "sig789"}
    assert Gateway.extract_signature(headers) == "sig789"
  end

  test "returns nil if signature header is missing" do
    headers = %{}
    assert Gateway.extract_signature(headers) == nil
  end

  test "returns nil for unknown header types" do
    assert Gateway.extract_signature(123) == nil
    assert Gateway.extract_signature(nil) == nil
  end

  describe "extract_signature/1" do
    test "extracts signature from list with X-Hub88-Signature" do
      headers = [{"X-Hub88-Signature", "abc"}]
      assert Challenge.Gateway.extract_signature(headers) == "abc"
    end

    test "returns nil if not found in list" do
      headers = [{"other-header", "val"}]
      assert Challenge.Gateway.extract_signature(headers) == nil
    end
  end
end
