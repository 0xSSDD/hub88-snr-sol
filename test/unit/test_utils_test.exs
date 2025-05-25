defmodule TestHelperTest do
  use ExUnit.Case
  alias TestHelper

  test "test keys exist and are valid" do
    # Verify keys exist
    assert File.exists?("priv/demo_priv.pem")
    assert File.exists?("priv/demo_pub.pem")

    # Verify keys can be used for signing
    test_data = "test data"
    signature = TestHelper.valid_signature(%{data: test_data})
    assert is_binary(signature)
    assert byte_size(signature) > 0
  end
end
