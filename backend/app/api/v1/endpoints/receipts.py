"""
EvenBill Receipts API Endpoints
Validates uploaded files, runs OCR extraction with editable outputs,
issues time-limited signed URLs, and enforces strict authorization.
"""

from typing import Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.receipt_service import ReceiptService
from app.core.rate_limit import rate_limit

router = APIRouter(prefix="/receipts", tags=["Receipts & OCR"])


@router.post(
    "/upload",
    response_model=APIResponse[Dict[str, Any]],
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit(max_requests=15, window_seconds=60, scope="receipt_upload"))]
)
async def upload_receipt(
    file: UploadFile = File(...),
    expense_id: Optional[str] = Form(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Upload and validate receipt image/PDF, run OCR line-item extraction,
    and return editable line items and duplicate detection indicators.
    """
    content = await file.read()
    receipt, is_duplicate = await ReceiptService.process_and_store_receipt(
        db=db,
        user=current_user,
        file_name=file.filename or "receipt.jpg",
        mime_type=file.content_type or "image/jpeg",
        content=content,
        expense_id=expense_id
    )

    import json
    ocr_payload = json.loads(receipt.raw_ocr_payload) if receipt.raw_ocr_payload else {}

    return APIResponse(data={
        "id": receipt.id,
        "file_name": receipt.file_name,
        "mime_type": receipt.mime_type,
        "file_size_bytes": receipt.file_size_bytes,
        "is_duplicate": is_duplicate,
        "ocr_status": receipt.ocr_status,
        "extracted_merchant": receipt.extracted_merchant,
        "extracted_total": float(receipt.extracted_total) if receipt.extracted_total else None,
        "extracted_currency": receipt.extracted_currency,
        "ocr_data": ocr_payload,
        "message": "Receipt processed successfully. Please review extracted line items before confirming."
    })


@router.get("/{receipt_id}/signed-url", response_model=APIResponse[Dict[str, Any]])
async def get_receipt_signed_url(
    receipt_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Generate an authenticated 15-minute presigned download URL for a receipt.
    Only authorized expense participants or group members may generate.
    """
    signed_data = await ReceiptService.generate_signed_download_url(
        db=db,
        receipt_id=receipt_id,
        current_user=current_user
    )
    return APIResponse(data=signed_data)


@router.delete("/{receipt_id}", response_model=APIResponse[Dict[str, Any]])
async def delete_receipt(
    receipt_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Soft-delete receipt into the 30-day statutory audit retention queue.
    """
    success = await ReceiptService.soft_delete_receipt(
        db=db,
        receipt_id=receipt_id,
        current_user=current_user
    )
    return APIResponse(data={
        "deleted": success,
        "receipt_id": receipt_id,
        "message": "Receipt archived. It will be permanently purged after the 30-day financial audit window."
    })
