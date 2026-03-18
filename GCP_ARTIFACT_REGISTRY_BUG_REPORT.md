# Bug Report: Google Cloud Artifact Registry (Ruby) - Corrupted Compact Index

**Summary:** 
Artifact Registry for Ruby serves a corrupted `/versions` file (Compact Index) containing raw binary bytes instead of hexadecimal checksums, causing standard Ruby clients like Bundler to crash during dependency resolution.

**Problem you have encountered:**
When running `bundle install` against a private Artifact Registry Ruby repository, the process fails with an `ArgumentError: invalid byte sequence in UTF-8`. 

Investigation revealed that the registry's `/versions` endpoint is injecting raw binary MD5/SHA bytes directly into the text stream for certain gems, instead of converting them to the required hexadecimal string format. Furthermore, the legacy index fallback (`/specs.4.8.gz`) is missing (404), leaving no standard way to resolve dependencies when the Compact Index is broken.

**What you expected to happen:**
1. The `/versions` file should be a valid UTF-8 text file where all checksums are represented as hexadecimal strings (e.g., `docile 1.4.1 b1ee719815c618dbad8a6ab38e19e072`).
2. The registry should support the legacy index (`/specs.4.8.gz`) as a fallback if the Compact Index fails.

**Steps to reproduce:**
1. Create a Ruby repository in Artifact Registry and push a few gems.
2. Query the `/versions` endpoint directly using an authentication token and inspect for non-printable characters:
   ```bash
   TOKEN=$(gcloud auth print-access-token)
   curl -s -H "Authorization: Bearer $TOKEN" \
     https://[REGION]-ruby.pkg.dev/[PROJECT]/[REPO]/versions | cat -v
   ```
   **Observed Output Evidence:**
   - Correct line (Hex checksum): `docile 1.4.1 b1ee719815c618dbad8a6ab38e19e072`
   - Corrupted lines (Binary raw bytes): `faraday 2.14.1 ^Y^PM-!p`, `cloud_events 0.9.0 PH^EM-^ZFM-wM-:M-SM-^FM-OM-]M-^[^CDM-fG`

3. Attempt to run `bundle install` in an environment isolated from `rubygems.org`. It will fail with:
   `ArgumentError: invalid byte sequence in UTF-8`

4. Attempt to run `gem install [GEM] --clear-sources --source [PRIVATE_REGISTRY_URL]`. It will fail with:
   `bad response Not Found 404 (.../specs.4.8.gz)`

**Other information (workarounds you have tried, documentation consulted, etc):**
- **Decompression Test:** Tested if the binary data was due to undeclared GZIP encoding. Running `curl --compressed | gunzip` returned `gzip: stdin: not in gzip format`, confirming the binary bytes are indeed part of the uncompressed text stream.
- **Local "Success" Illusion:** `gem install` appears to work in some local environments because it silently falls back to `index.rubygems.org` to fetch metadata when the private registry fails. However, in restricted CI/CD environments (like Cloud Build) without public access, the failure is total.
- **Implemented Workaround ("Brute-Force Vendoring"):** To unblock deployments, we bypassed the registry's index system entirely. We implemented a Ruby script in `cloudbuild.yaml` that parses the `Gemfile.lock`, constructs the direct URLs for the `.gem` files (e.g., `.../gems/name-1.2.3.gem`), and downloads them using `curl`. These files are then cached in `vendor/cache` so that the buildpack can install them without querying the corrupted registry index.
