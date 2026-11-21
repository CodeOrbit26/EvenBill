"""
Object Storage Provider Interface
Defines the contract for uploading, presigning, and deleting receipt objects and attachments.
"""

from abc import ABC, abstractmethod


class IObjectStorageProvider(ABC):
    @abstractmethod
    async def upload_file(self, file_name: str, content: bytes, content_type: str) -> str:
        """Store binary payload into storage and return the permanent object storage key."""
        pass

    @abstractmethod
    async def generate_presigned_download_url(self, object_key: str, expires_in_seconds: int = 900) -> str:
        """Generate a time-limited presigned URL (default 15 minutes) for authorized downloading."""
        pass

    @abstractmethod
    async def generate_presigned_upload_url(self, object_key: str, content_type: str, expires_in_seconds: int = 900) -> str:
        """Generate a time-limited presigned upload URL for direct client multipart uploads."""
        pass

    @abstractmethod
    async def delete_file(self, object_key: str) -> bool:
        """Delete or soft-quarantine an object from storage."""
        pass

