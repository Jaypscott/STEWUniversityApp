import os
import tempfile
from pathlib import Path


TEST_DATABASE_PATH = (
    Path(tempfile.gettempdir()) / f"stew-university-tests-{os.getpid()}.db"
)

# Configure the database before pytest imports app modules and creates the
# SQLAlchemy engine. Always override the ambient value so tests cannot reset a
# developer or production database accidentally.
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{TEST_DATABASE_PATH}"


def pytest_sessionfinish() -> None:
    TEST_DATABASE_PATH.unlink(missing_ok=True)
