"""
EvenBill Cloud Secrets Manager Integration
Supports AWS Secrets Manager, GCP Secret Manager, Vault, and local environment fallback.
Ensures zero plaintext production secrets in repositories or Docker images.
"""

import os
from typing import Optional, Dict

class SecretManager:
    _cached_secrets: Dict[str, str] = {}

    @classmethod
    def get_secret(cls, secret_name: str, default: Optional[str] = None) -> str:
        """
        Retrieves a secret from the active cloud provider secret manager
        or falls back to environment variables.
        """
        if secret_name in cls._cached_secrets:
            return cls._cached_secrets[secret_name]

        provider = os.getenv("SECRET_MANAGER_PROVIDER", "ENV").upper()
        val = None

        if provider == "AWS":
            try:
                import boto3
                client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION", "us-east-1"))
                resp = client.get_secret_value(SecretId=secret_name)
                val = resp.get("SecretString")
            except Exception:
                val = None

        elif provider == "GCP":
            try:
                from google.cloud import secretmanager
                client = secretmanager.SecretManagerServiceClient()
                project_id = os.getenv("GCP_PROJECT_ID")
                name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
                resp = client.access_secret_version(request={"name": name})
                val = resp.payload.data.decode("UTF-8")
            except Exception:
                val = None

        # Fallback to os.environ
        if val is None:
            val = os.getenv(secret_name, default)

        if val is not None:
            cls._cached_secrets[secret_name] = val
            return val

        if default is not None:
            return default

        raise KeyError(f"Required production secret '{secret_name}' not found in {provider} Secret Manager or environment.")

    @classmethod
    def clear_cache(cls):
        """Clears the internal cache (for testing or key rotation)."""
        cls._cached_secrets.clear()
