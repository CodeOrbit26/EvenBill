"""
Transactional Email Provider Interface
Defines the contract for dispatching verification links, group invitations, and security notices.
"""

from abc import ABC, abstractmethod
from typing import List, Optional


class IEmailProvider(ABC):
    @abstractmethod
    async def send_email(
        self,
        recipient: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None
    ) -> bool:
        """Send an individual transactional email message."""
        pass

    @abstractmethod
    async def send_verification_email(self, recipient: str, verification_url: str) -> bool:
        """Send account email verification message."""
        pass

    @abstractmethod
    async def send_group_invitation(
        self, recipient: str, inviter_name: str, group_name: str, invite_url: str
    ) -> bool:
        """Send a group invitation message with secure claim link."""
        pass

