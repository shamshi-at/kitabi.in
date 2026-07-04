"""One-off helper: generate the Apple "Secret Key (for OAuth)" JWT that
Supabase's Apple provider needs. Run locally, never commit the output or the
.p8 file. Apple caps validity at 6 months — rerun before it expires.

Usage:
    api/.venv/bin/python3 api/scripts/gen_apple_secret.py \\
        --team-id 62686X3746 \\
        --key-id <KEY_ID_FROM_APPLE> \\
        --client-id in.kitabi.kitabi.web \\
        --key-file ~/Downloads/AuthKey_<KEY_ID>.p8

Copies the result straight to your clipboard (pbcopy) — it is never printed.
"""

import argparse
import subprocess
import time

import jwt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team-id", required=True, help="Apple Developer Team ID")
    parser.add_argument("--key-id", required=True, help="Key ID from the Keys page")
    parser.add_argument(
        "--client-id",
        required=True,
        help="The Services ID used for the OAuth/web flow, e.g. in.kitabi.kitabi.web",
    )
    parser.add_argument("--key-file", required=True, help="Path to the downloaded .p8 file")
    args = parser.parse_args()

    with open(args.key_file) as f:
        private_key = f.read()

    now = int(time.time())
    token = jwt.encode(
        {
            "iss": args.team_id,
            "iat": now,
            "exp": now + 15777000,  # ~6 months — Apple's maximum
            "aud": "https://appleid.apple.com",
            "sub": args.client_id,
        },
        private_key,
        algorithm="ES256",
        headers={"kid": args.key_id},
    )

    subprocess.run(["pbcopy"], input=token.encode())
    print(f"Done — {len(token)}-character secret copied to your clipboard.")
    print("Paste it into Supabase → Authentication → Providers → Apple → Secret Key (for OAuth).")


if __name__ == "__main__":
    main()
