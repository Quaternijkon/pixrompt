import hashlib
import os
import re
import secrets
from dataclasses import dataclass
from pathlib import Path


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class BlobStoreError(ValueError):
    """Base class for blob storage errors."""


class InvalidBlobHash(BlobStoreError):
    """Raised when a blob hash path parameter is not a lowercase SHA-256 hex digest."""


class BlobHashMismatch(BlobStoreError):
    """Raised when uploaded bytes do not match the path SHA-256."""


class BlobNotFound(FileNotFoundError):
    """Raised when a blob file is missing from filesystem storage."""


@dataclass(frozen=True)
class StoredBlob:
    sha256: str
    path: Path
    relative_path: str
    size_bytes: int
    created: bool


def is_valid_sha256(value: str) -> bool:
    return bool(SHA256_RE.fullmatch(value))


class BlobStore:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)

    def path_for(self, sha256: str) -> Path:
        self._validate_hash(sha256)
        return self.root / sha256[:2] / sha256[2:4] / sha256

    def relative_path_for(self, sha256: str) -> str:
        self._validate_hash(sha256)
        return f"{sha256[:2]}/{sha256[2:4]}/{sha256}"

    def exists(self, sha256: str) -> bool:
        return self.path_for(sha256).is_file()

    def stat(self, sha256: str) -> os.stat_result:
        path = self.path_for(sha256)
        if not path.is_file():
            raise BlobNotFound(sha256)
        return path.stat()

    def put(self, sha256: str, data: bytes) -> StoredBlob:
        self._validate_hash(sha256)
        actual = hashlib.sha256(data).hexdigest()
        if actual != sha256:
            raise BlobHashMismatch(f"body SHA-256 {actual} does not match {sha256}")

        path = self.path_for(sha256)
        if path.is_file():
            return StoredBlob(
                sha256=sha256,
                path=path,
                relative_path=self.relative_path_for(sha256),
                size_bytes=path.stat().st_size,
                created=False,
            )

        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = path.with_name(f".{path.name}.{secrets.token_hex(8)}.tmp")
        try:
            with temp_path.open("xb") as handle:
                handle.write(data)
            os.replace(temp_path, path)
        finally:
            if temp_path.exists():
                temp_path.unlink()

        return StoredBlob(
            sha256=sha256,
            path=path,
            relative_path=self.relative_path_for(sha256),
            size_bytes=len(data),
            created=True,
        )

    def _validate_hash(self, sha256: str) -> None:
        if not is_valid_sha256(sha256):
            raise InvalidBlobHash("expected lowercase SHA-256 hex digest")
