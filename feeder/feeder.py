"""
FHIR Feeder - reads JSON files from a directory and sends them to a FHIR server.

Configuration is loaded from a .env file in the same directory as this script.
See .env.example for available variables.
"""

import json
import os
import sys
import argparse
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from dotenv import load_dotenv

# Load .env from the directory where this script lives
_ENV_PATH = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=_ENV_PATH)

# ── Configuration (all values come from .env) ────────────────────────────────
FHIR_BASE_URL = os.getenv("FHIR_BASE_URL", "http://localhost:52773/fhir/r4")
INPUT_DIR = os.getenv("INPUT_DIR", "../synthea/output/fhir")
MAX_WORKERS = int(os.getenv("MAX_WORKERS", "8"))
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "30"))

_user = os.getenv("FHIR_USER")
_password = os.getenv("FHIR_PASSWORD")
BASIC_AUTH: Optional[tuple] = (_user, _password) if _user and _password else None
# ────────────────────────────────────────────────────────────────────────────

EXTRA_HEADERS: dict = {
    "Accept": "application/fhir+json",
    "Content-Type": "application/fhir+json",
}


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(threadName)s] %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("feeder")


@dataclass
class Result:
    file: str
    success: bool
    status_code: Optional[int] = None
    method: str = ""
    url: str = ""
    error: Optional[str] = None


def build_session() -> requests.Session:
    """Create a requests Session with retry logic."""
    session = requests.Session()
    retry = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[502, 503, 504],
        allowed_methods=["POST", "PUT"],
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    if BASIC_AUTH:
        session.auth = BASIC_AUTH
    session.headers.update(EXTRA_HEADERS)
    return session


def classify_response(status_code: int) -> str:
    if status_code in (200, 201):
        return "OK"
    if status_code == 400:
        return "Bad Request"
    if status_code == 401:
        return "Unauthorized"
    if status_code == 403:
        return "Forbidden"
    if status_code == 404:
        return "Not Found"
    if status_code == 409:
        return "Conflict"
    if status_code == 422:
        return "Unprocessable Entity"
    if 400 <= status_code < 500:
        return f"Client Error {status_code}"
    if 500 <= status_code < 600:
        return f"Server Error {status_code}"
    return f"HTTP {status_code}"


def send_file(file_path: Path, base_url: str, session: requests.Session) -> Result:
    fname = file_path.name
    try:
        raw = file_path.read_text(encoding="utf-8")
        resource = json.loads(raw)
    except Exception as exc:
        log.error("[SKIP] %s — cannot parse JSON: %s", fname, exc)
        return Result(file=fname, success=False, error=f"JSON parse error: {exc}")

    resource_type = resource.get("resourceType")
    if not resource_type:
        log.error("[SKIP] %s — missing resourceType", fname)
        return Result(file=fname, success=False, error="Missing resourceType")

    if resource_type == "Bundle":
        method = "POST"
        url = base_url.rstrip("/")
    else:
        resource_id = resource.get("id")
        if not resource_id:
            log.error("[SKIP] %s — non-Bundle resource has no id", fname)
            return Result(
                file=fname,
                success=False,
                method="PUT",
                error="Missing resource id",
            )
        method = "PUT"
        url = f"{base_url.rstrip('/')}/{resource_type}/{resource_id}"

    try:
        response = session.request(
            method=method,
            url=url,
            data=raw.encode("utf-8"),
            timeout=REQUEST_TIMEOUT,
        )
        status = response.status_code
        label = classify_response(status)
        success = status in (200, 201)

        if success:
            log.info("[OK  %d] %-6s %s  ← %s", status, method, url, fname)
        else:
            log.warning(
                "[ERR %d] %-6s %s  ← %s  (%s)",
                status,
                method,
                url,
                fname,
                label,
            )

        return Result(
            file=fname,
            success=success,
            status_code=status,
            method=method,
            url=url,
        )

    except requests.exceptions.Timeout:
        log.error("[TIMEOUT] %s — %s %s", fname, method, url)
        return Result(
            file=fname,
            success=False,
            method=method,
            url=url,
            error="Request timeout",
        )
    except requests.exceptions.ConnectionError as exc:
        log.error("[CONN ERR] %s — %s", fname, exc)
        return Result(file=fname, success=False, method=method, url=url, error=str(exc))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Send FHIR JSON files to a FHIR server."
    )
    parser.add_argument(
        "--dir",
        default=INPUT_DIR,
        help=f"Directory with JSON files (default: {INPUT_DIR})",
    )
    parser.add_argument(
        "--url",
        default=FHIR_BASE_URL,
        help=f"FHIR base URL (default: {FHIR_BASE_URL})",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=MAX_WORKERS,
        help=f"Concurrent threads (default: {MAX_WORKERS})",
    )
    args = parser.parse_args()

    input_path = Path(args.dir).resolve()
    if not input_path.is_dir():
        log.error("Directory not found: %s", input_path)
        sys.exit(1)

    files = sorted(input_path.glob("*.json"))
    if not files:
        log.warning("No JSON files found in %s", input_path)
        sys.exit(0)

    log.info("FHIR Feeder starting")
    log.info("  Server  : %s", args.url)
    log.info("  Source  : %s", input_path)
    log.info("  Files   : %d", len(files))
    log.info("  Threads : %d", args.workers)

    session = build_session()
    results: list[Result] = []

    with ThreadPoolExecutor(max_workers=args.workers, thread_name_prefix="fhir") as pool:
        futures = {
            pool.submit(send_file, f, args.url, session): f for f in files
        }
        for future in as_completed(futures):
            results.append(future.result())

    # ── Summary ──────────────────────────────────────────────────────────────
    total = len(results)
    ok = sum(1 for r in results if r.success)
    errors = total - ok

    skipped = [r for r in results if r.status_code is None]
    server_errors = [r for r in results if r.status_code and not r.success]

    print("\n" + "═" * 60)
    print("  FHIR Feeder — Summary")
    print("═" * 60)
    print(f"  Total files   : {total}")
    print(f"  Sent OK       : {ok}")
    print(f"  Server errors : {len(server_errors)}")
    print(f"  Skipped/local : {len(skipped)}")
    print("═" * 60)

    if server_errors:
        print("\n  Files with server errors:")
        for r in server_errors:
            print(f"    [{r.status_code}] {r.file}")

    if skipped:
        print("\n  Skipped files:")
        for r in skipped:
            print(f"    {r.file}  ({r.error})")

    sys.exit(0 if errors == 0 else 1)


if __name__ == "__main__":
    main()
