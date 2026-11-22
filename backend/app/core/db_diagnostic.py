"""
Database Connection URL Diagnostic Module
Performs non-sensitive URL parsing, sanitization checks, and DNS resolution diagnostics
before database connection attempts.

Zero Credentials Exposed: Never logs passwords or raw connection strings.
"""

import socket
from typing import Dict, Any
from sqlalchemy.engine import make_url


def diagnose_database_url(url_string: str) -> Dict[str, Any]:
    """
    Parses DATABASE_URL, logs safe metadata (driver, host, port, user, has_password),
    checks for common configuration anomalies (quotes, whitespace, malformed host),
    and executes a non-blocking DNS resolution test.

    NEVER logs credentials or the full raw URL.
    """
    print("\n=======================================================")
    print("--- [DATABASE_URL STARTUP DIAGNOSTIC] ---")

    if not url_string:
        print("ERROR: DATABASE_URL is empty or not provided.")
        print("--- [END DATABASE_URL DIAGNOSTIC] ---")
        print("=======================================================\n")
        return {"success": False, "error": "Empty DATABASE_URL"}

    # 1. Structural / Framing checks
    has_leading_quote = url_string.startswith(('"', "'"))
    has_trailing_quote = url_string.endswith(('"', "'"))
    has_whitespace = (url_string != url_string.strip())

    if has_leading_quote or has_trailing_quote:
        print("WARNING: DATABASE_URL contains surrounding quotes (' or \").")
    if has_whitespace:
        print("WARNING: DATABASE_URL contains leading or trailing whitespace.")

    cleaned_url = url_string.strip().strip('"\'')

    # 2. Parse URL with SQLAlchemy make_url
    try:
        parsed = make_url(cleaned_url)
    except Exception as exc:
        print(f"ERROR: Failed to parse DATABASE_URL with make_url(): {exc}")
        print("--- [END DATABASE_URL DIAGNOSTIC] ---")
        print("=======================================================\n")
        return {"success": False, "error": str(exc)}

    driver = parsed.drivername
    host = parsed.host
    port = parsed.port or (5432 if "postgresql" in driver else None)
    username = parsed.username
    has_password = bool(parsed.password)

    # 3. Log safe parameters (Zero secrets)
    print(f"Driver:             {driver}")
    print(f"Parsed Hostname:    {host}")
    print(f"Parsed Port:        {port}")
    print(f"Parsed Username:    {username}")
    print(f"Password Present:   {has_password}")

    # 4. Hostname anomaly checks
    if host:
        if "@" in host:
            print("CRITICAL ANOMALY: Parsed hostname contains '@'.")
            print("  -> Your database password likely contains an unescaped '@' character!")
            print("  -> Percent-encode it as '%40' in your environment settings.")
        if any(c in host for c in [":", "/", "?", "#", " ", "\\"]):
            print("CRITICAL ANOMALY: Parsed hostname contains illegal URI characters (colon, slash, hash, or space).")
            print("  -> Check for unencoded special characters in your password or a malformed URL structure.")
    elif "sqlite" not in driver:
        print("ERROR: Parsed hostname is empty or None.")

    # 5. DNS Resolution Test
    dns_success = False
    resolved_ips = []
    if host and "sqlite" not in driver:
        print(f"Testing DNS resolution for hostname: '{host}' on port {port}...")
        try:
            addr_info = socket.getaddrinfo(host, port, socket.AF_UNSPEC, socket.SOCK_STREAM)
            resolved_ips = sorted(list({sockaddr[0] for _, _, _, _, sockaddr in addr_info}))
            dns_success = True
            print(f"DNS Resolution:     SUCCESS -> Resolved {len(resolved_ips)} IP address(es): {resolved_ips}")
        except socket.gaierror as gai_err:
            print(f"DNS Resolution:     FAILED -> socket.gaierror: {gai_err}")
            print(f"  [Detail: The hostname '{host}' could not be resolved by the system DNS resolver]")
        except Exception as exc:
            print(f"DNS Resolution:     FAILED -> {type(exc).__name__}: {exc}")
    else:
        print("DNS Resolution:     SKIPPED (Local file / SQLite database)")
        dns_success = True

    print("--- [END DATABASE_URL DIAGNOSTIC] ---")
    print("=======================================================\n")

    return {
        "success": dns_success,
        "driver": driver,
        "host": host,
        "port": port,
        "username": username,
        "has_password": has_password,
        "resolved_ips": resolved_ips,
    }
