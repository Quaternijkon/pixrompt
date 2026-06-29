from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ApiModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True)


class LoginRequest(ApiModel):
    email: str
    password: str
    device_id: str = Field(alias="deviceId", min_length=1)


class LoginResponse(ApiModel):
    token: str
    token_type: Literal["bearer"] = Field("bearer", alias="tokenType")
    expires_at: int = Field(alias="expiresAt")
    email: str


class SessionResponse(ApiModel):
    email: str
    device_id: str = Field(alias="deviceId")
    expires_at: int = Field(alias="expiresAt")


class BlobRef(ApiModel):
    sha256: str
    image_key: str = Field(alias="imageKey")
    size_bytes: int = Field(alias="sizeBytes", ge=0)
    mime_type: str | None = Field(default=None, alias="mimeType")


class PushImage(ApiModel):
    image_uid: str = Field(alias="imageUid", min_length=1)
    base_server_version: int = Field(0, alias="baseServerVersion", ge=0)
    updated_at: int = Field(alias="updatedAt", ge=0)
    record: dict[str, Any]
    blob: BlobRef | None = None


class PushDelete(ApiModel):
    image_uid: str = Field(alias="imageUid", min_length=1)
    base_server_version: int = Field(0, alias="baseServerVersion", ge=0)
    deleted_at: int = Field(alias="deletedAt", ge=0)


class PushRequest(ApiModel):
    device_id: str = Field(alias="deviceId", min_length=1)
    base_cursor: int = Field(0, alias="baseCursor", ge=0)
    images: list[PushImage] = Field(default_factory=list)
    deleted: list[PushDelete] = Field(default_factory=list)


class PullRequest(ApiModel):
    device_id: str = Field(alias="deviceId", min_length=1)
    cursor: int = Field(0, ge=0)
    known_blob_sha256: list[str] = Field(default_factory=list, alias="knownBlobSha256")


class AcceptedItem(ApiModel):
    image_uid: str = Field(alias="imageUid")
    server_version: int = Field(alias="serverVersion")


class RejectedItem(ApiModel):
    image_uid: str = Field(alias="imageUid")
    server_version: int = Field(alias="serverVersion")
    reason: str


class PushResponse(ApiModel):
    cursor: int
    server_time: int = Field(alias="serverTime")
    accepted: list[AcceptedItem]
    rejected: list[RejectedItem]
    missing_blobs: list[str] = Field(alias="missingBlobs")


class PullBlob(ApiModel):
    sha256: str
    image_key: str = Field(alias="imageKey")
    size_bytes: int = Field(alias="sizeBytes", ge=0)


class PullChange(ApiModel):
    type: Literal["upsert"] = "upsert"
    image_uid: str = Field(alias="imageUid")
    server_version: int = Field(alias="serverVersion")
    updated_at: int = Field(alias="updatedAt")
    record: dict[str, Any]
    blob: PullBlob | None = None


class PullDeleted(ApiModel):
    image_uid: str = Field(alias="imageUid")
    server_version: int = Field(alias="serverVersion")
    deleted_at: int = Field(alias="deletedAt")


class PullResponse(ApiModel):
    cursor: int
    server_time: int = Field(alias="serverTime")
    changes: list[PullChange]
    deleted: list[PullDeleted]
    missing_blobs: list[str] = Field(alias="missingBlobs")
