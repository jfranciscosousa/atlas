defmodule Atlas.Images do
  use Ash.Domain,
    otp_app: :atlas,
    extensions: [AshTypescript.Rpc, AshAi]

  typescript_rpc do
    resource Atlas.Images.Image do
      rpc_action :get_image_url, :signed_url
    end
  end

  tools do
    tool :upload_image, Atlas.Images.Image, :upload_from_url,
      description:
        "Store an image from a public http(s) URL. Returns its id and the Markdown to put it in text: ![](atlas-image:ID)."

    tool :upload_image_data, Atlas.Images.Image, :upload_from_base64,
      description:
        "Store an image that you hold as base64 text (for example one the user attached), when it has no public URL. Up to about 6 MB; use upload_image with a URL for larger ones. Returns its id and the Markdown to put it in text: ![](atlas-image:ID)."
  end

  resources do
    resource Atlas.Images.Image
  end
end
