defmodule Atlas.StorageTest do
  use ExUnit.Case, async: false

  test "the R2 adapter issues a short-lived presigned URL for the configured bucket" do
    original = Application.fetch_env!(:atlas, Atlas.Storage)

    Application.put_env(:atlas, Atlas.Storage,
      adapter: Atlas.Storage.R2,
      bucket: "atlas-test",
      endpoint_url: "https://acct.r2.cloudflarestorage.com",
      access_key_id: "AKIATEST",
      secret_access_key: "very-secret-value"
    )

    on_exit(fn -> Application.put_env(:atlas, Atlas.Storage, original) end)

    url = Atlas.Storage.signed_url("campaigns/c/images/i.webp")
    uri = URI.parse(url)
    query = URI.decode_query(uri.query)

    assert uri.host == "acct.r2.cloudflarestorage.com"
    assert uri.path == "/atlas-test/campaigns/c/images/i.webp"
    assert query["X-Amz-Expires"] == "600"
    assert query["X-Amz-Signature"] =~ ~r/\A[0-9a-f]{64}\z/
    refute url =~ "very-secret-value"
  end
end
