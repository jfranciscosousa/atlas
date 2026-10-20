defmodule Atlas.Images do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource Atlas.Images.Image do
      rpc_action :get_image_url, :signed_url
    end
  end

  resources do
    resource Atlas.Images.Image
  end
end
