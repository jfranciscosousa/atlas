defmodule Atlas.StorageTest do
  use ExUnit.Case, async: false

  test "R2 deletion signs requests, accepts missing objects and reports failures" do
    original_storage = Application.fetch_env!(:atlas, Atlas.Storage)
    original_options = Req.default_options()

    Application.put_env(:atlas, Atlas.Storage,
      adapter: Atlas.Storage.R2,
      bucket: "atlas-test",
      endpoint_url: "https://acct.r2.cloudflarestorage.com",
      access_key_id: "AKIATEST",
      secret_access_key: "very-secret-value"
    )

    Req.default_options(plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.put_env(:atlas, Atlas.Storage, original_storage)
      Req.default_options(original_options)
    end)

    for status <- [204, 404, 403] do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.host == "acct.r2.cloudflarestorage.com"
        assert conn.request_path == "/atlas-test/images/test.webp"
        assert ["AWS4-HMAC-SHA256" <> _] = Plug.Conn.get_req_header(conn, "authorization")
        Plug.Conn.send_resp(conn, status, "")
      end)

      expected = if status == 403, do: {:error, {:r2_status, 403}}, else: :ok
      assert Atlas.Storage.delete("images/test.webp") == expected
    end
  end

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
