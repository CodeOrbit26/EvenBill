"""
Integration Tests for Swagger UI, ReDoc, and OpenAPI Schema Endpoints
Verifies documentation routing, schema validity, CSP compatibility, and redirects.
"""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_swagger_ui_endpoint(client: AsyncClient):
    """Verify /api/v1/docs serves Swagger UI HTML with CSP compatible with CDN assets."""
    response = await client.get("/api/v1/docs")
    assert response.status_code == 200
    assert "text/html" in response.headers.get("content-type", "")
    assert "SwaggerUIBundle" in response.text
    assert "/api/v1/openapi.json" in response.text

    # Verify CSP allows jsdelivr CDN and inline script for Swagger UI initialization
    csp = response.headers.get("content-security-policy", "")
    assert "https://cdn.jsdelivr.net" in csp
    assert "'unsafe-inline'" in csp


@pytest.mark.asyncio
async def test_openapi_json_endpoint(client: AsyncClient):
    """Verify /api/v1/openapi.json returns a valid OpenAPI 3.x schema document."""
    response = await client.get("/api/v1/openapi.json")
    assert response.status_code == 200
    assert "application/json" in response.headers.get("content-type", "")

    schema = response.json()
    assert "openapi" in schema
    assert schema["openapi"].startswith("3.")
    assert schema["info"]["title"] == "EvenBill"
    assert "paths" in schema
    assert len(schema["paths"]) > 0

    # Verify key API routes are present in OpenAPI schema
    assert "/api/v1/groups/" in schema["paths"]
    assert "/api/v1/expenses/" in schema["paths"]
    assert "/api/v1/settlements/" in schema["paths"]
    assert "/health" in schema["paths"]


@pytest.mark.asyncio
async def test_redoc_endpoint(client: AsyncClient):
    """Verify /api/v1/redoc serves ReDoc documentation HTML with compatible CSP."""
    response = await client.get("/api/v1/redoc")
    assert response.status_code == 200
    assert "text/html" in response.headers.get("content-type", "")
    assert "/api/v1/openapi.json" in response.text

    csp = response.headers.get("content-security-policy", "")
    assert "https://cdn.jsdelivr.net" in csp


@pytest.mark.asyncio
async def test_top_level_docs_redirect(client: AsyncClient):
    """Verify GET /docs redirects to /api/v1/docs."""
    response = await client.get("/docs", follow_redirects=False)
    assert response.status_code == 307
    assert response.headers.get("location") == "/api/v1/docs"


@pytest.mark.asyncio
async def test_top_level_openapi_redirect(client: AsyncClient):
    """Verify GET /openapi.json redirects to /api/v1/openapi.json."""
    response = await client.get("/openapi.json", follow_redirects=False)
    assert response.status_code == 307
    assert response.headers.get("location") == "/api/v1/openapi.json"


@pytest.mark.asyncio
async def test_api_endpoints_retain_strict_csp(client: AsyncClient):
    """Verify standard API endpoints retain strict CSP without CDN origins."""
    response = await client.get("/health")
    assert response.status_code == 200
    csp = response.headers.get("content-security-policy", "")
    assert "https://cdn.jsdelivr.net" not in csp
    assert "script-src 'self';" in csp
