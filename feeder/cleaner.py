"""
FHIR Cleaner - deletes all resources of specified type(s) from a FHIR server.

Reads configuration from .env in the same directory:
    FHIR_BASE_URL   - Base URL of the FHIR server (no trailing slash)
    FHIR_USER       - Basic auth username (optional)
    FHIR_PASSWORD   - Basic auth password (optional)

Usage:
    python cleaner.py --types Subscription
    python cleaner.py --types Subscription Patient Encounter

Algorithm (per resource type):
    1. GET /{Type}?_count=100  (first page)
    2. Collect all resource IDs from the Bundle entries
    3. DELETE /{Type}/{id} for each ID
    4. Follow the 'next' link in the Bundle to get the next page
    5. Repeat until no 'next' link remains
    6. Re-run rounds until nothing is deleted in a round
    7. Final search to confirm zero remaining resources
"""

import argparse
import os
import sys
import logging
from pathlib import Path
from typing import Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from dotenv import load_dotenv

# Load .env from the directory where this script lives
_ENV_PATH = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=_ENV_PATH)

FHIR_BASE_URL: str = os.getenv("FHIR_BASE_URL", "http://localhost:52773/fhir/r4")
_user = os.getenv("FHIR_USER")
_password = os.getenv("FHIR_PASSWORD")
BASIC_AUTH: Optional[tuple] = (_user, _password) if _user and _password else None

PAGE_SIZE = 100  # _count per search page

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("cleaner")


def build_session() -> requests.Session:
    session = requests.Session()
    retry = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[502, 503, 504],
        allowed_methods=["GET", "DELETE"],
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    if BASIC_AUTH:
        session.auth = BASIC_AUTH
    session.headers.update(
        {
            "Accept": "application/fhir+json",
            "Content-Type": "application/fhir+json",
        }
    )
    return session


def get_next_link(bundle: dict) -> Optional[str]:
    """Return the 'next' page URL from a FHIR Bundle, or None."""
    for link in bundle.get("link", []):
        if link.get("relation") == "next":
            return link.get("url")
    return None


def extract_ids(bundle: dict) -> list[str]:
    """Collect resource IDs from Bundle entries."""
    ids = []
    for entry in bundle.get("entry", []):
        resource = entry.get("resource", {})
        rid = resource.get("id")
        if rid:
            ids.append(rid)
    return ids


def search_page(session: requests.Session, url: str) -> dict:
    """Fetch a single search page and return the parsed Bundle."""
    response = session.get(url, timeout=30)
    if response.status_code != 200:
        log.error("Search failed: HTTP %d — %s", response.status_code, url)
        sys.exit(1)
    bundle = response.json()
    if bundle.get("resourceType") != "Bundle":
        log.error("Expected Bundle, got: %s", bundle.get("resourceType"))
        sys.exit(1)
    return bundle


def delete_resource(session: requests.Session, base_url: str, resource_type: str, rid: str) -> bool:
    """DELETE a single resource by type and id. Returns True on success."""
    url = f"{base_url.rstrip('/')}/{resource_type}/{rid}"
    response = session.delete(url, timeout=30)
    if response.status_code in (200, 204):
        log.info("[DELETED %d] %s/%s", response.status_code, resource_type, rid)
        return True
    else:
        log.warning(
            "[DELETE FAILED %d] %s/%s — %s",
            response.status_code,
            resource_type,
            rid,
            response.text[:200],
        )
        return False


def count_total(bundle: dict) -> Optional[int]:
    """Return Bundle.total if present."""
    return bundle.get("total")


def clean_resource_type(
    session: requests.Session, base_url: str, resource_type: str
) -> tuple[int, int]:
    """Delete all resources of a given type. Returns (deleted, failed) counts."""
    deleted_total = 0
    failed_total = 0
    round_num = 0

    while True:
        round_num += 1
        first_url = f"{base_url}/{resource_type}?_count={PAGE_SIZE}"
        log.info("[%s] Round %d — fetching first page", resource_type, round_num)

        bundle = search_page(session, first_url)
        total_on_server = count_total(bundle)
        if total_on_server is not None:
            log.info("[%s] Server reports %d resource(s) remaining", resource_type, total_on_server)

        round_deleted = 0
        round_failed = 0
        page_num = 0
        current_bundle = bundle

        while True:
            page_num += 1
            ids = extract_ids(current_bundle)

            if not ids:
                log.info("[%s] Page %d: no entries", resource_type, page_num)
                break

            log.info("[%s] Page %d: %d resource(s) — deleting...", resource_type, page_num, len(ids))
            for rid in ids:
                if delete_resource(session, base_url, resource_type, rid):
                    round_deleted += 1
                    deleted_total += 1
                else:
                    round_failed += 1
                    failed_total += 1

            next_url = get_next_link(current_bundle)
            if not next_url:
                break
            log.info("[%s] Following 'next' link...", resource_type)
            current_bundle = search_page(session, next_url)

        log.info(
            "[%s] Round %d done: deleted %d, failed %d",
            resource_type, round_num, round_deleted, round_failed,
        )

        if round_deleted == 0:
            break

    # Final verification
    verification_bundle = search_page(session, f"{base_url}/{resource_type}?_count=1")
    remaining = count_total(verification_bundle)
    if remaining:
        log.warning("[%s] %d resource(s) still on server!", resource_type, remaining)
    else:
        log.info("[%s] 0 resources remaining. Clean.", resource_type)

    return deleted_total, failed_total


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Delete all resources of specified type(s) from a FHIR server."
    )
    parser.add_argument(
        "--types",
        nargs="+",
        default=["Subscription"],
        metavar="ResourceType",
        help="One or more FHIR resource types to delete (default: Subscription)",
    )
    args = parser.parse_args()

    base_url = FHIR_BASE_URL.rstrip("/")
    session = build_session()

    log.info("FHIR Cleaner starting")
    log.info("  Server : %s", base_url)
    log.info("  Auth   : %s", "enabled" if BASIC_AUTH else "disabled")
    log.info("  Types  : %s", ", ".join(args.types))

    summary: dict[str, tuple[int, int]] = {}
    for resource_type in args.types:
        log.info("\n=== Cleaning %s ===", resource_type)
        deleted, failed = clean_resource_type(session, base_url, resource_type)
        summary[resource_type] = (deleted, failed)

    print("\n" + "═" * 60)
    print("  FHIR Cleaner — Summary")
    print("═" * 60)
    any_failures = False
    for rt, (deleted, failed) in summary.items():
        print(f"  {rt:<30} deleted: {deleted:>4}   failed: {failed:>4}")
        if failed:
            any_failures = True
    print("═" * 60)

    sys.exit(1 if any_failures else 0)


if __name__ == "__main__":
    main()
