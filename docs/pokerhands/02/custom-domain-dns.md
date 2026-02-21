# Custom domain DNS for hand-history API

The API is served at **`https://api.allansattelbergrivera.com`** (or whatever you set in `var.api_domain`).

After applying Terraform, point your DNS for that domain to the API Gateway regional endpoint:

- **Output**: Run `terraform output api_gateway_domain_target` to get the target hostname (e.g. `d-xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`).
- **DNS**: Create a **CNAME** (or **A/ALIAS** if your DNS provider supports alias records) for `api.allansattelbergrivera.com` pointing to that hostname.

Example (if using Route 53): create an A record with alias target set to the regional API Gateway domain name.

Once DNS has propagated, the hand-history API will be available at:

- `https://api.allansattelbergrivera.com/hand-history/upload-url` (POST)
- `https://api.allansattelbergrivera.com/hand-history/files` (GET)
- `https://api.allansattelbergrivera.com/hand-history/download` (GET, with `jobId` query param)
