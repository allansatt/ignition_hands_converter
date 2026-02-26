# Custom domain DNS for hand-history API

The API is served at **`https://api.allansattelbergrivera.com`** (or whatever you set in `var.api_domain`).

After applying Terraform, point your DNS for that domain to the API Gateway regional endpoint:

- **Output**: Run `terraform output hand_history_api_domain_target` to get the target hostname (e.g. `d-xxxxxxxxxx.execute-api.us-east-1.amazonaws.com`).
- **DNS**: Create a **CNAME** (or **A/ALIAS**) for `hand-history.allansattelbergrivera.com` pointing to that hostname.

Once DNS has propagated, the hand-history API will be available at:

- `https://api.allansattelbergrivera.com/hand-history/upload-url` (POST)
- `https://api.allansattelbergrivera.com/hand-history/files` (GET)
- `https://api.allansattelbergrivera.com/hand-history/download` (GET, with `jobId` query param)
