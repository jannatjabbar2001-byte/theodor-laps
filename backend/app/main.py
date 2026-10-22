import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
import os
import re
from uuid import uuid4
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.responses import FileResponse, Response
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, ConfigDict, EmailStr
from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint, cast, create_engine, delete, func, inspect as sqlalchemy_inspect, or_, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.engine import make_url
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, relationship, sessionmaker

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")
MEDIA = ROOT / "media"
MEDIA.mkdir(exist_ok=True)
ENVIRONMENT = os.getenv("ENVIRONMENT", "development").strip().lower()
if ENVIRONMENT not in {"development", "production"}:
    raise RuntimeError("ENVIRONMENT must be either development or production")
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{ROOT / 'alkawn.db'}")
if DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
R2_ENDPOINT = os.getenv("R2_ENDPOINT")
R2_BUCKET = os.getenv("R2_BUCKET")
R2_ACCESS_KEY_ID = os.getenv("R2_ACCESS_KEY_ID") or os.getenv("R2_ACCESSKEY_ID")
R2_SECRET_ACCESS_KEY = os.getenv("R2_SECRET_ACCESS_KEY")
FRONTEND_ORIGIN = os.getenv("FRONTEND_ORIGIN")

def cors_origins() -> list[str]:
    origin = (FRONTEND_ORIGIN or "").strip()
    if ENVIRONMENT == "development":
        if not origin or origin == "*":
            return ["*"]
        origins = {origin}
        parsed_origin = urlsplit(origin)
        if parsed_origin.hostname in {"localhost", "127.0.0.1"}:
            alternate_host = "127.0.0.1" if parsed_origin.hostname == "localhost" else "localhost"
            alternate_origin = parsed_origin._replace(netloc=f"{alternate_host}:{parsed_origin.port}" if parsed_origin.port else alternate_host)
            origins.add(alternate_origin.geturl())
        return sorted(origins)
    if not origin or origin == "*" or "," in origin:
        raise RuntimeError("FRONTEND_ORIGIN must be a single origin in production")
    try:
        parsed_origin = urlsplit(origin)
        valid_origin = (
            parsed_origin.scheme == "https"
            and bool(parsed_origin.hostname)
            and not parsed_origin.username
            and not parsed_origin.password
            and parsed_origin.path in {"", "/"}
            and not parsed_origin.query
            and not parsed_origin.fragment
        )
    except ValueError:
        valid_origin = False
    if not valid_origin:
        raise RuntimeError("FRONTEND_ORIGIN must be a valid origin in production")
    return [origin]

CORS_ORIGINS = cors_origins()
if ENVIRONMENT == "production":
    required_settings = {
        "SUPABASE_URL": SUPABASE_URL,
        "SUPABASE_SERVICE_ROLE_KEY": SUPABASE_SERVICE_ROLE_KEY,
        "DATABASE_URL": os.getenv("DATABASE_URL"),
        "JWT_SECRET": os.getenv("JWT_SECRET"),
        "R2_ENDPOINT": R2_ENDPOINT,
        "R2_BUCKET": R2_BUCKET,
        "R2_ACCESS_KEY_ID": R2_ACCESS_KEY_ID,
        "R2_SECRET_ACCESS_KEY": R2_SECRET_ACCESS_KEY,
        "FRONTEND_ORIGIN": FRONTEND_ORIGIN,
    }
    missing_settings = [name for name, value in required_settings.items() if not value]
    if missing_settings:
        raise RuntimeError(f"Missing production settings: {', '.join(missing_settings)}")
    if DATABASE_URL.startswith("sqlite"):
        raise RuntimeError("DATABASE_URL must use PostgreSQL in production")
    database_url = make_url(DATABASE_URL)
    supabase_host = urlsplit(SUPABASE_URL).hostname or ""
    project_ref = supabase_host.split(".", 1)[0]
    database_host = database_url.host or ""
    database_user = database_url.username or ""
    direct_connection = database_host.endswith(f".{project_ref}.supabase.co")
    pooler_connection = (
        database_host.endswith(".pooler.supabase.com")
        and database_user.endswith(f".{project_ref}")
    )
    if not project_ref or not (direct_connection or pooler_connection):
        raise RuntimeError("DATABASE_URL does not point to the configured Supabase project")
engine_options = {"connect_args": {"check_same_thread": False}} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, **engine_options)
SessionLocal = sessionmaker(bind=engine, autoflush=False)
SECRET = os.getenv("JWT_SECRET")
if not SECRET:
    raise RuntimeError("JWT_SECRET must be configured")
if SECRET == "development-only-change-me":
    raise RuntimeError("JWT_SECRET contains an insecure default")
pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2 = OAuth2PasswordBearer(tokenUrl="/auth/login")

class Base(DeclarativeBase): pass
class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(180), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(30), default="user")
    is_original: Mapped[bool] = mapped_column(Boolean, default=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    permissions: Mapped[list["Permission"]] = relationship(back_populates="user", cascade="all, delete-orphan")
class Item(Base):
    __tablename__ = "items"
    id: Mapped[int] = mapped_column(primary_key=True)
    key: Mapped[str] = mapped_column(String(80), unique=True)
    title: Mapped[str] = mapped_column(String(160))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
class Permission(Base):
    __tablename__ = "permissions"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    item_key: Mapped[str] = mapped_column(String(80), index=True)
    resource_key: Mapped[str | None] = mapped_column(String(180), nullable=True)
    allowed: Mapped[bool] = mapped_column(Boolean, default=True)
    user: Mapped[User] = relationship(back_populates="permissions")
class RoleItem(Base):
    __tablename__ = "role_items"
    id: Mapped[int] = mapped_column(primary_key=True)
    role: Mapped[str] = mapped_column(String(30), index=True)
    item_key: Mapped[str] = mapped_column(String(80), index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
class Video(Base):
    __tablename__ = "videos"
    id: Mapped[int] = mapped_column(primary_key=True)
    language: Mapped[str] = mapped_column(String(40), index=True)
    title: Mapped[str] = mapped_column(String(180))
    url: Mapped[str] = mapped_column(String(500))
    object_key: Mapped[str | None] = mapped_column(String(500), nullable=True, index=True)
    access: Mapped[str] = mapped_column(String(20), default="public")
    published: Mapped[bool] = mapped_column(Boolean, default=True)

class Progress(Base):
    __tablename__ = "progress"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    video_id: Mapped[int] = mapped_column(ForeignKey("videos.id"), index=True)
    position_seconds: Mapped[float] = mapped_column(default=0)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

class CommunityProfile(Base):
    __tablename__ = "community_profiles"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(40), default="")
    avatar_filename: Mapped[str | None] = mapped_column(String(80), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

class CommunityConversation(Base):
    __tablename__ = "community_conversations"
    __table_args__ = (
        UniqueConstraint("member_low_id", "member_high_id"),
        CheckConstraint("member_low_id < member_high_id", name="ck_community_conversation_member_order"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    member_low_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    member_high_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc), index=True)

class CommunityMembership(Base):
    __tablename__ = "community_memberships"
    conversation_id: Mapped[int] = mapped_column(ForeignKey("community_conversations.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    last_read_message_id: Mapped[int | None] = mapped_column(Integer, nullable=True)

class CommunityMessage(Base):
    __tablename__ = "community_messages"
    __table_args__ = (
        Index("ix_community_messages_conversation_id_id", "conversation_id", "id"),
        Index("ix_community_messages_created_at", "created_at"),
        Index("ix_community_messages_reply_to_id", "reply_to_id"),
        Index(
            "ix_community_public_message_expiry",
            "expires_at",
            postgresql_where=text("conversation_id IS NULL"),
            sqlite_where=text("conversation_id IS NULL"),
        ),
        CheckConstraint(
            "(conversation_id IS NULL AND expires_at IS NOT NULL) OR "
            "(conversation_id IS NOT NULL AND expires_at IS NULL)",
            name="ck_community_message_expiry_scope",
        ),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    sender_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    conversation_id: Mapped[int | None] = mapped_column(ForeignKey("community_conversations.id", ondelete="CASCADE"), nullable=True)
    reply_to_id: Mapped[int | None] = mapped_column(ForeignKey("community_messages.id", ondelete="SET NULL"), nullable=True)
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(default=lambda: datetime.now(timezone.utc))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

if DATABASE_URL.startswith("sqlite"):
    Base.metadata.create_all(engine)
else:
    inspector = sqlalchemy_inspect(engine)
    missing_tables = sorted(set(Base.metadata.tables) - set(inspector.get_table_names()))
    missing_columns = {
        table.name: sorted(
            set(table.columns.keys())
            - {column["name"] for column in inspector.get_columns(table.name)}
        )
        for table in Base.metadata.sorted_tables
        if table.name in inspector.get_table_names()
        and set(table.columns.keys())
        - {column["name"] for column in inspector.get_columns(table.name)}
    }
    if missing_tables or missing_columns:
        raise RuntimeError(
            "PostgreSQL schema is incomplete; apply the required migrations "
            f"(missing tables: {missing_tables}, missing columns: {missing_columns})"
        )

ITEMS = {
    "programming": "البرمجة",
    "school": "المدرسة",
    "library": "المكتبة",
    "million-road": "طريق المليون",
    "exploration": "الاستكشافات",
    "achievements": "الإنجازات",
    "community": "المجتمع",
    "settings": "الإعدادات",
    "about": "عن ثيودور",
    "health": "الصحة",
    "administration": "الإدارة",
}
ROLE_ITEMS = {
    "superadmin": set(ITEMS),
    "admin": set(ITEMS) - {"administration"},
    "user": set(ITEMS) - {"health", "administration"},
}

def seed_system() -> None:
    with SessionLocal() as session:
        if DATABASE_URL.startswith("sqlite"):
            columns = {row[1] for row in session.execute(text("PRAGMA table_info(users)"))}
            if "is_original" not in columns:
                session.execute(text("ALTER TABLE users ADD COLUMN is_original BOOLEAN NOT NULL DEFAULT 0"))
                session.commit()
            video_columns = {row[1] for row in session.execute(text("PRAGMA table_info(videos)"))}
            if "object_key" not in video_columns:
                session.execute(text("ALTER TABLE videos ADD COLUMN object_key VARCHAR(500)"))
                session.commit()
            profile_columns = {row[1] for row in session.execute(text("PRAGMA table_info(community_profiles)"))}
            if "avatar_filename" not in profile_columns:
                session.execute(text("ALTER TABLE community_profiles ADD COLUMN avatar_filename VARCHAR(80)"))
                session.commit()
        for key, title in ITEMS.items():
            if not session.scalar(select(Item).where(Item.key == key)):
                session.add(Item(key=key, title=title, enabled=True))
        for role, allowed_items in ROLE_ITEMS.items():
            for item_key in ITEMS:
                if not session.scalar(select(RoleItem).where(RoleItem.role == role, RoleItem.item_key == item_key)):
                    session.add(RoleItem(role=role, item_key=item_key, enabled=item_key in allowed_items))
        originals = (
            (
                ("1", "1", "superadmin"),
                ("2", "2", "admin"),
                ("3", "3", "user"),
            )
            if ENVIRONMENT == "development" and DATABASE_URL.startswith("sqlite")
            else ()
        )
        for username, password, role in originals:
            user = session.scalar(select(User).where(User.email == username))
            if not user:
                user = User(email=username, password_hash=pwd.hash(password), role=role, is_original=True)
                session.add(user)
                session.flush()
            else:
                user.role = role
                user.is_original = True
            for item_key in ROLE_ITEMS[role]:
                if not session.scalar(select(Permission).where(Permission.user_id == user.id, Permission.item_key == item_key, Permission.resource_key.is_(None))):
                    session.add(Permission(user_id=user.id, item_key=item_key, allowed=True))
        session.commit()

seed_system()

COMMUNITY_RETENTION_LOCK_ID = 86520423107
logger = logging.getLogger(__name__)

def expired_public_messages_statement():
    return delete(CommunityMessage).where(
        CommunityMessage.conversation_id.is_(None),
        CommunityMessage.expires_at <= func.now(),
    )

def purge_expired_public_messages() -> int:
    if not DATABASE_URL.startswith("postgresql"):
        return 0
    with engine.connect() as connection:
        acquired = connection.execute(
            text("SELECT pg_try_advisory_lock(:lock_id)"),
            {"lock_id": COMMUNITY_RETENTION_LOCK_ID},
        ).scalar_one()
        connection.commit()
        if not acquired:
            return 0
        try:
            result = connection.execute(expired_public_messages_statement())
            deleted_count = result.rowcount or 0
            connection.commit()
            return deleted_count
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.execute(
                text("SELECT pg_advisory_unlock(:lock_id)"),
                {"lock_id": COMMUNITY_RETENTION_LOCK_ID},
            )
            connection.commit()

async def _community_retention_worker() -> None:
    while True:
        try:
            await asyncio.to_thread(purge_expired_public_messages)
        except Exception as error:
            logger.error("Community retention cleanup failed (%s)", type(error).__name__)
        await asyncio.sleep(60)

@asynccontextmanager
async def lifespan(_: FastAPI):
    worker = None
    if DATABASE_URL.startswith("postgresql"):
        worker = asyncio.create_task(_community_retention_worker())
    try:
        yield
    finally:
        if worker is not None:
            worker.cancel()
            try:
                await worker
            except asyncio.CancelledError:
                pass

app = FastAPI(title="الكون الشامل API", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)
class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    email: str
    role: str
    is_original: bool
class Token(BaseModel): access_token: str; token_type: str
class PermissionIn(BaseModel): user_id: int; item_key: str; resource_key: str | None = None; allowed: bool = True
class VideoIn(BaseModel): language: str; title: str; url: str | None = None; access: str = "public"
class VideoPublishIn(BaseModel): language: str; title: str; object_key: str; access: str = "public"
class RoleIn(BaseModel): role: str
class ProgressIn(BaseModel): video_id: int; position_seconds: float; completed: bool = False
class PresignIn(BaseModel): filename: str; content_type: str = "video/mp4"
class CommunityProfileIn(BaseModel): display_name: str
class CommunityMessageIn(BaseModel):
    body: str
    reply_to_id: int | None = None
class CommunityConversationIn(BaseModel): user_id: int

def normalized_title(title: str) -> str:
    return re.sub(r"[^\w\u0600-\u06ff]+", "", title.casefold())

def similar_title(left: str, right: str) -> bool:
    first, second = normalized_title(left), normalized_title(right)
    return bool(first and second) and (
        first in second or second in first or SequenceMatcher(None, first, second).ratio() >= 0.82
    )

def ensure_unique_video_title(data: VideoIn, session: Session) -> None:
    existing = session.scalars(
        select(Video).where(Video.language == data.language, Video.access == data.access)
    )
    if any(similar_title(data.title, video.title) for video in existing):
        raise HTTPException(status_code=409, detail="يوجد مقطع بعنوان مطابق أو مشابه بالفعل")

def db():
    with SessionLocal() as session: yield session
def current_user(token: Annotated[str, Depends(oauth2)], session: Annotated[Session, Depends(db)]) -> User:
    try:
        payload = jwt.decode(token, SECRET, algorithms=["HS256"])
        user_id = int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="جلسة غير صالحة")
    user = session.get(User, user_id)
    if not user or not user.active: raise HTTPException(status_code=401, detail="المستخدم غير فعال")
    return user
def require_admin(user: Annotated[User, Depends(current_user)]) -> User:
    if user.role not in {"superadmin", "admin", "supervisor"}: raise HTTPException(status_code=403, detail="صلاحية الإدارة مطلوبة")
    return user
def require_superadmin(user: Annotated[User, Depends(current_user)]) -> User:
    if user.role != "superadmin" or not user.is_original or user.email != "1": raise HTTPException(status_code=403, detail="صلاحية المدير الأصلي مطلوبة")
    return user

def r2_client():
    if not all((R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY)):
        raise HTTPException(status_code=503, detail="R2 غير مضبوط على الخادم")
    import boto3
    return boto3.client("s3", endpoint_url=R2_ENDPOINT, aws_access_key_id=R2_ACCESS_KEY_ID, aws_secret_access_key=R2_SECRET_ACCESS_KEY, region_name="auto")
def can_access(user: User, item_key: str, resource_key: str | None, session: Session) -> bool:
    item = session.scalar(select(Item).where(Item.key == item_key, Item.enabled.is_(True)))
    if not item: return False
    if user.role == "superadmin": return True
    role_item = session.scalar(select(RoleItem).where(RoleItem.role == user.role, RoleItem.item_key == item_key))
    if role_item and not role_item.enabled: return False
    return session.scalar(select(Permission).where(Permission.user_id == user.id, Permission.item_key == item_key, Permission.resource_key == resource_key, Permission.allowed.is_(True))) is not None or session.scalar(select(Permission).where(Permission.user_id == user.id, Permission.item_key == item_key, Permission.resource_key.is_(None), Permission.allowed.is_(True))) is not None

def require_community_access(user: User, session: Session) -> None:
    if not can_access(user, "community", None, session):
        raise HTTPException(status_code=403, detail="ليس لديك صلاحية دخول المجتمع")

def community_user_data(user: User, session: Session) -> dict:
    profile = session.get(CommunityProfile, user.id)
    return {
        "id": user.id,
        "display_name": profile.display_name if profile and profile.display_name else f"عضو {user.id}",
        "avatar_url": f"/community/avatars/{user.id}?v={profile.avatar_filename}" if profile and profile.avatar_filename else None,
        "role": user.role,
    }

async def store_community_avatar(user_id: int, image: UploadFile, profile: CommunityProfile, session: Session) -> None:
    content_type = (image.content_type or "").lower()
    formats = {
        "image/png": ("png", b"\x89PNG\r\n\x1a\n"),
        "image/jpeg": ("jpg", b"\xff\xd8\xff"),
        "image/webp": ("webp", b"RIFF"),
    }
    image_format = formats.get(content_type)
    if image_format is None:
        raise HTTPException(status_code=415, detail="اختر صورة PNG أو JPEG أو WebP")
    data = await image.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="يجب ألا يتجاوز حجم الصورة 2 ميغابايت")
    extension, signature = image_format
    if not data.startswith(signature) or (extension == "webp" and data[8:12] != b"WEBP"):
        raise HTTPException(status_code=415, detail="محتوى الملف لا يطابق نوع الصورة")

    if DATABASE_URL.startswith("postgresql"):
        filename = f"community-avatars/{user_id}/{uuid4().hex}.{extension}"
        client = r2_client()
        try:
            client.put_object(
                Bucket=R2_BUCKET,
                Key=filename,
                Body=data,
                ContentType=content_type,
            )
        except Exception as error:
            raise HTTPException(status_code=502, detail="تعذر حفظ الصورة في R2") from error
        previous_filename = profile.avatar_filename
        profile.avatar_filename = filename
        try:
            session.commit()
        except Exception:
            session.rollback()
            try:
                client.delete_object(Bucket=R2_BUCKET, Key=filename)
            except Exception:
                pass
            raise
        if previous_filename and previous_filename.startswith("community-avatars/"):
            try:
                client.delete_object(Bucket=R2_BUCKET, Key=previous_filename)
            except Exception as error:
                logger.warning("Unable to remove replaced community avatar (%s)", type(error).__name__)
        return

    avatar_directory = MEDIA / "community-avatars"
    avatar_directory.mkdir(parents=True, exist_ok=True)
    filename = f"{user_id}-{uuid4().hex}.{extension}"
    avatar_path = avatar_directory / filename
    avatar_path.write_bytes(data)
    previous_filename = profile.avatar_filename
    profile.avatar_filename = filename
    try:
        session.commit()
    except Exception:
        avatar_path.unlink(missing_ok=True)
        raise
    if previous_filename:
        previous_path = avatar_directory / Path(previous_filename).name
        if previous_path != avatar_path:
            previous_path.unlink(missing_ok=True)

def community_message_data(messages: list[CommunityMessage], viewer_id: int, session: Session) -> list[dict]:
    sender_ids = {message.sender_id for message in messages}
    if not sender_ids:
        return []
    reply_ids = {message.reply_to_id for message in messages if message.reply_to_id is not None}
    replies = session.scalars(select(CommunityMessage).where(CommunityMessage.id.in_(reply_ids))).all() if reply_ids else []
    reply_sender_ids = {reply.sender_id for reply in replies}
    users = session.scalars(select(User).where(User.id.in_(sender_ids))).all()
    reply_users = session.scalars(select(User).where(User.id.in_(reply_sender_ids))).all() if reply_sender_ids else []
    profiles = session.scalars(select(CommunityProfile).where(CommunityProfile.user_id.in_(sender_ids))).all()
    reply_profiles = session.scalars(select(CommunityProfile).where(CommunityProfile.user_id.in_(reply_sender_ids))).all() if reply_sender_ids else []
    users_by_id = {member.id: member for member in users}
    reply_names = {profile.user_id: profile.display_name for profile in reply_profiles if profile.display_name}
    reply_users_by_id = {member.id: member for member in reply_users}
    replies_by_id = {reply.id: reply for reply in replies}
    names_by_id = {profile.user_id: profile.display_name for profile in profiles if profile.display_name}
    avatars_by_id = {profile.user_id: profile.avatar_filename for profile in profiles if profile.avatar_filename}
    return [
        {
            "id": message.id,
            "body": message.body,
            "created_at": message.created_at.isoformat(),
            "expires_at": message.expires_at.isoformat() if message.expires_at else None,
            "reply_to_id": message.reply_to_id,
            "reply_to": (
                {
                    "id": replies_by_id[message.reply_to_id].id,
                    "body": replies_by_id[message.reply_to_id].body,
                    "sender_name": reply_names.get(
                        replies_by_id[message.reply_to_id].sender_id,
                        f"عضو {replies_by_id[message.reply_to_id].sender_id}",
                    ),
                }
                if message.reply_to_id in replies_by_id
                and replies_by_id[message.reply_to_id].sender_id in reply_users_by_id
                else None
            ),
            "sender": {
                "id": message.sender_id,
                "display_name": names_by_id.get(message.sender_id, f"عضو {message.sender_id}"),
                "avatar_url": f"/community/avatars/{message.sender_id}?v={avatars_by_id[message.sender_id]}" if message.sender_id in avatars_by_id else None,
            },
            "is_mine": message.sender_id == viewer_id,
        }
        for message in messages
        if message.sender_id in users_by_id
    ]

def select_community_messages(session: Session, conversation_id: int | None, before_id: int | None, after_id: int, limit: int) -> list[CommunityMessage]:
    statement = select(CommunityMessage).where(CommunityMessage.conversation_id == conversation_id)
    if conversation_id is None:
        statement = statement.where(CommunityMessage.expires_at > datetime.now(timezone.utc))
    if before_id is not None:
        statement = statement.where(CommunityMessage.id < before_id).order_by(CommunityMessage.id.desc())
    elif after_id > 0:
        statement = statement.where(CommunityMessage.id > after_id).order_by(CommunityMessage.id.asc())
    else:
        statement = statement.order_by(CommunityMessage.id.desc())
    messages = list(session.scalars(statement.limit(max(1, min(limit, 100)))).all())
    if before_id is None and after_id == 0 or before_id is not None:
        messages.reverse()
    return messages

def require_conversation_member(conversation_id: int, user: User, session: Session) -> tuple[CommunityConversation, CommunityMembership]:
    conversation = session.get(CommunityConversation, conversation_id)
    if not conversation or user.id not in {conversation.member_low_id, conversation.member_high_id}:
        raise HTTPException(status_code=404, detail="المحادثة غير موجودة")
    membership = session.scalar(select(CommunityMembership).where(
        CommunityMembership.conversation_id == conversation_id,
        CommunityMembership.user_id == user.id,
    ))
    if not membership:
        raise HTTPException(status_code=404, detail="المحادثة غير موجودة")
    return conversation, membership

def require_reply_target(reply_to_id: int | None, conversation_id: int | None, session: Session) -> None:
    if reply_to_id is None:
        return
    target = session.scalar(select(CommunityMessage).where(
        CommunityMessage.id == reply_to_id,
        CommunityMessage.conversation_id == conversation_id,
    ))
    if not target:
        raise HTTPException(status_code=404, detail="رسالة الرد غير موجودة في هذه المحادثة")

@app.get("/health")
def health(): return {"status": "ok", "service": "alkawn-alshamil"}

@app.post("/auth/login")
def login(form: Annotated[OAuth2PasswordRequestForm, Depends()], session: Annotated[Session, Depends(db)]):
    user = session.scalar(select(User).where(User.email == form.username))
    if (
        not user
        or not user.active
        or (ENVIRONMENT == "production" and user.email == "1")
        or not pwd.verify(form.password, user.password_hash)
    ):
        raise HTTPException(status_code=401, detail="بيانات الدخول غير صحيحة")
    expires = datetime.now(timezone.utc) + timedelta(hours=12)
    token = jwt.encode({"sub": str(user.id), "exp": expires}, SECRET, algorithm="HS256")
    return {"access_token": token, "token_type": "bearer"}

@app.get("/auth/me", response_model=UserOut)
def me(user: Annotated[User, Depends(current_user)]):
    return user

@app.post("/auth/register", response_model=UserOut)
async def register(request: Request, session: Annotated[Session, Depends(db)]):
    image = None
    if request.headers.get("content-type", "").startswith("multipart/form-data"):
        form = await request.form()
        username = str(form.get("username", "")).strip().lower()
        password = str(form.get("password", ""))
        display_name = str(form.get("display_name", "")).strip()
        image = form.get("avatar")
        if image is not None and not all(hasattr(image, name) for name in ("read", "content_type")):
            raise HTTPException(status_code=400, detail="ملف الصورة غير صالح")
    else:
        data = await request.json()
        username = str(data.get("username", "")).strip().lower()
        password = str(data.get("password", ""))
        display_name = str(data.get("display_name", "")).strip()
    if username == "1" or not username or len(password) < 8:
        raise HTTPException(status_code=400, detail="اسم المستخدم وكلمة المرور مطلوبان")
    if display_name and (not 2 <= len(display_name) <= 40 or any(ord(character) < 32 for character in display_name)):
        raise HTTPException(status_code=422, detail="الاسم الظاهر يجب أن يكون بين حرفين و40 حرفًا")
    if session.scalar(select(User).where(User.email == username)):
        raise HTTPException(status_code=409, detail="اسم المستخدم مستخدم من قبل")
    user = User(email=username, password_hash=pwd.hash(password), role="user")
    session.add(user)
    session.flush()
    profile = CommunityProfile(user_id=user.id, display_name=display_name)
    session.add(profile)
    if image is not None:
        await store_community_avatar(user.id, image, profile, session)
    else:
        session.commit()
    session.refresh(user)
    return user

@app.get("/community/profile")
def get_community_profile(user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    return community_user_data(user, session)

@app.put("/community/profile")
def update_community_profile(data: CommunityProfileIn, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    display_name = data.display_name.strip()
    if not 2 <= len(display_name) <= 40 or any(ord(character) < 32 for character in display_name):
        raise HTTPException(status_code=422, detail="الاسم الظاهر يجب أن يكون بين حرفين و40 حرفًا")
    profile = session.get(CommunityProfile, user.id)
    if not profile:
        profile = CommunityProfile(user_id=user.id, display_name=display_name)
        session.add(profile)
    else:
        profile.display_name = display_name
    session.commit()
    session.refresh(profile)
    return community_user_data(user, session)

@app.post("/community/profile/avatar")
async def update_community_avatar(user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)], image: UploadFile = File(...)):
    require_community_access(user, session)
    profile = session.get(CommunityProfile, user.id)
    if not profile:
        profile = CommunityProfile(user_id=user.id, display_name="")
        session.add(profile)
        session.flush()
    await store_community_avatar(user.id, image, profile, session)
    session.refresh(profile)
    return community_user_data(user, session)

@app.get("/community/avatars/{user_id}")
def get_community_avatar(user_id: int, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    target = session.get(User, user_id)
    if not target or not target.active or not can_access(target, "community", None, session):
        raise HTTPException(status_code=404, detail="الصورة غير موجودة")
    profile = session.get(CommunityProfile, user_id)
    if not profile or not profile.avatar_filename:
        raise HTTPException(status_code=404, detail="الصورة غير موجودة")
    if profile.avatar_filename.startswith("community-avatars/"):
        if ".." in profile.avatar_filename.split("/"):
            raise HTTPException(status_code=404, detail="الصورة غير موجودة")
        try:
            image = r2_client().get_object(
                Bucket=R2_BUCKET,
                Key=profile.avatar_filename,
            )
            content = image["Body"].read(2 * 1024 * 1024 + 1)
        except Exception as error:
            raise HTTPException(status_code=502, detail="تعذر تحميل الصورة من R2") from error
        if len(content) > 2 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="حجم الصورة المخزنة غير صالح")
        media_type = image.get("ContentType") or {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".webp": "image/webp",
        }.get(Path(profile.avatar_filename).suffix.lower())
        if media_type not in {"image/png", "image/jpeg", "image/webp"}:
            raise HTTPException(status_code=415, detail="نوع الصورة المخزنة غير صالح")
        return Response(
            content=content,
            media_type=media_type,
            headers={"Cache-Control": "private, max-age=3600"},
        )

    filename = Path(profile.avatar_filename).name
    avatar_path = MEDIA / "community-avatars" / filename
    if not avatar_path.is_file():
        raise HTTPException(status_code=404, detail="الصورة غير موجودة")
    media_type = {".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp"}.get(avatar_path.suffix.lower())
    if not media_type:
        raise HTTPException(status_code=404, detail="الصورة غير موجودة")
    return FileResponse(avatar_path, media_type=media_type, headers={"Cache-Control": "private, max-age=3600"})

@app.get("/community/users")
def community_users(search: str = "", limit: int = 40, user: User = Depends(current_user), session: Session = Depends(db)):
    require_community_access(user, session)
    statement = select(User).where(User.active.is_(True), User.id != user.id)
    normalized_search = search.strip()[:40]
    if normalized_search:
        statement = statement.outerjoin(CommunityProfile, CommunityProfile.user_id == User.id).where(
            or_(
                CommunityProfile.display_name.ilike(f"%{normalized_search}%"),
                cast(User.id, String).ilike(f"%{normalized_search}%"),
            )
        )
    users = session.scalars(statement.order_by(User.id.desc()).limit(max(1, min(limit, 100)))).all()
    return [community_user_data(member, session) for member in users if can_access(member, "community", None, session)]

@app.get("/community/messages")
def public_community_messages(user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)], before_id: int | None = None, after_id: int = 0, limit: int = 50):
    require_community_access(user, session)
    messages = select_community_messages(session, None, before_id, after_id, limit)
    return community_message_data(messages, user.id, session)

@app.post("/community/messages")
def send_public_community_message(data: CommunityMessageIn, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    body = data.body.strip()
    if not body or len(body) > 2000:
        raise HTTPException(status_code=422, detail="يجب أن تحتوي الرسالة على 1 إلى 2000 حرف")
    require_reply_target(data.reply_to_id, None, session)
    created_at = datetime.now(timezone.utc)
    message = CommunityMessage(
        sender_id=user.id,
        body=body,
        reply_to_id=data.reply_to_id,
        created_at=created_at,
        expires_at=created_at + timedelta(hours=24),
    )
    session.add(message)
    session.commit()
    session.refresh(message)
    return community_message_data([message], user.id, session)[0]

@app.get("/community/conversations")
def list_community_conversations(user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    memberships = session.scalars(select(CommunityMembership).where(CommunityMembership.user_id == user.id)).all()
    result = []
    for membership in memberships:
        conversation = session.get(CommunityConversation, membership.conversation_id)
        if not conversation:
            continue
        other_id = conversation.member_high_id if conversation.member_low_id == user.id else conversation.member_low_id
        other_user = session.get(User, other_id)
        if not other_user or not other_user.active or not can_access(other_user, "community", None, session):
            continue
        latest = session.scalar(select(CommunityMessage).where(
            CommunityMessage.conversation_id == conversation.id
        ).order_by(CommunityMessage.id.desc()).limit(1))
        unread_count = session.scalar(select(func.count(CommunityMessage.id)).where(
            CommunityMessage.conversation_id == conversation.id,
            CommunityMessage.sender_id != user.id,
            CommunityMessage.id > (membership.last_read_message_id or 0),
        )) or 0
        result.append({
            "id": conversation.id,
            "user": community_user_data(other_user, session),
            "unread_count": unread_count,
            "last_message": latest.body if latest else None,
            "updated_at": (latest.created_at if latest else conversation.updated_at).isoformat(),
        })
    return sorted(result, key=lambda item: item["updated_at"], reverse=True)

@app.post("/community/conversations")
def create_community_conversation(data: CommunityConversationIn, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    if data.user_id == user.id:
        raise HTTPException(status_code=400, detail="لا يمكن بدء محادثة مع حسابك")
    other_user = session.get(User, data.user_id)
    if not other_user or not other_user.active or not can_access(other_user, "community", None, session):
        raise HTTPException(status_code=404, detail="المستخدم غير متاح في المجتمع")
    member_low_id, member_high_id = sorted((user.id, other_user.id))
    conversation = session.scalar(select(CommunityConversation).where(
        CommunityConversation.member_low_id == member_low_id,
        CommunityConversation.member_high_id == member_high_id,
    ))
    if not conversation:
        conversation = CommunityConversation(member_low_id=member_low_id, member_high_id=member_high_id)
        session.add(conversation)
        try:
            session.flush()
            session.add_all([
                CommunityMembership(conversation_id=conversation.id, user_id=member_low_id),
                CommunityMembership(conversation_id=conversation.id, user_id=member_high_id),
            ])
            session.commit()
        except IntegrityError:
            session.rollback()
            conversation = session.scalar(select(CommunityConversation).where(
                CommunityConversation.member_low_id == member_low_id,
                CommunityConversation.member_high_id == member_high_id,
            ))
            if not conversation:
                raise HTTPException(status_code=409, detail="تعذر إنشاء المحادثة، حاول مجددًا")
    return {"id": conversation.id, "user": community_user_data(other_user, session)}

@app.get("/community/conversations/{conversation_id}/messages")
def private_community_messages(conversation_id: int, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)], before_id: int | None = None, after_id: int = 0, limit: int = 50):
    require_community_access(user, session)
    _, membership = require_conversation_member(conversation_id, user, session)
    messages = select_community_messages(session, conversation_id, before_id, after_id, limit)
    if messages:
        membership.last_read_message_id = max(membership.last_read_message_id or 0, messages[-1].id)
        session.commit()
    return community_message_data(messages, user.id, session)

@app.post("/community/conversations/{conversation_id}/messages")
def send_private_community_message(conversation_id: int, data: CommunityMessageIn, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    require_community_access(user, session)
    conversation, _ = require_conversation_member(conversation_id, user, session)
    body = data.body.strip()
    if not body or len(body) > 2000:
        raise HTTPException(status_code=422, detail="يجب أن تحتوي الرسالة على 1 إلى 2000 حرف")
    require_reply_target(data.reply_to_id, conversation_id, session)
    message = CommunityMessage(
        sender_id=user.id,
        conversation_id=conversation_id,
        reply_to_id=data.reply_to_id,
        body=body,
    )
    conversation.updated_at = datetime.now(timezone.utc)
    session.add(message)
    session.commit()
    session.refresh(message)
    return community_message_data([message], user.id, session)[0]

@app.get("/public/videos")
def public_videos(user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    videos = session.scalars(select(Video).where(Video.published.is_(True))).all()
    return [{"id": video.id, "language": video.language, "title": video.title, "access": video.access, "url": None} for video in videos if can_access(user, "programming", None, session) and (user.role in {"superadmin", "admin"} or video.access == "public")]

@app.post("/public/videos/upload")
def public_upload_video():
    raise HTTPException(status_code=403, detail="رفع الفيديو متاح للمدير الأصلي فقط عبر R2")

@app.post("/admin/videos/upload")
def upload_video(_: Annotated[User, Depends(require_superadmin)]):
    raise HTTPException(status_code=410, detail="استخدم presign ثم PUT إلى R2 ثم publish")

@app.get("/content/{item_key}")
def content(item_key: str, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    if not can_access(user, item_key, None, session): raise HTTPException(status_code=403, detail="هذا المحتوى غير مصرح به لحسابك")
    return {"item": item_key, "message": "محتوى محمي متاح"}

@app.get("/programming/{language}/videos")
def list_videos(language: str, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    videos = session.scalars(select(Video).where(Video.language == language, Video.published.is_(True))).all()
    visible = videos if user.role in {"superadmin", "admin"} else [video for video in videos if video.access == "public" and can_access(user, "programming", None, session)]
    return [{"id": video.id, "language": video.language, "title": video.title, "access": video.access, "url": None} for video in visible]
@app.put("/admin/permissions")
def set_permission(data: PermissionIn, _: Annotated[User, Depends(require_admin)], session: Annotated[Session, Depends(db)]):
    permission = session.scalar(select(Permission).where(Permission.user_id == data.user_id, Permission.item_key == data.item_key, Permission.resource_key == data.resource_key))
    if permission: permission.allowed = data.allowed
    else: session.add(Permission(**data.model_dump()))
    session.commit(); return {"saved": True}

@app.get("/admin/dashboard")
def admin_dashboard(_: Annotated[User, Depends(require_admin)], session: Annotated[Session, Depends(db)]):
    users = list(session.scalars(select(User)))
    return {
        "accounts": len(users),
        "users": sum(user.role == "user" for user in users),
        "supervisors": sum(user.role in {"admin", "supervisor"} for user in users),
        "admins": sum(user.role == "superadmin" for user in users),
        "videos": session.query(Video).count(),
    }

@app.get("/admin/users")
def admin_users(_: Annotated[User, Depends(require_admin)], session: Annotated[Session, Depends(db)]):
    return [{"id": user.id, "username": user.email, "role": user.role, "active": user.active, "is_original": user.is_original} for user in session.scalars(select(User).order_by(User.id))]

@app.put("/admin/users/{user_id}/role")
def change_role(user_id: int, data: RoleIn, actor: Annotated[User, Depends(require_superadmin)], session: Annotated[Session, Depends(db)]):
    if data.role not in {"user", "admin"}:
        raise HTTPException(status_code=400, detail="الرتبة المسموحة user أو admin")
    user = session.get(User, user_id)
    if not user: raise HTTPException(status_code=404, detail="الحساب غير موجود")
    if user.is_original or user.email == "1": raise HTTPException(status_code=403, detail="لا يمكن تغيير رتبة السوبر أدمن الأصلي")
    user.role = data.role
    for item_key in ROLE_ITEMS[data.role]:
        if not session.scalar(select(Permission).where(Permission.user_id == user.id, Permission.item_key == item_key, Permission.resource_key.is_(None))):
            session.add(Permission(user_id=user.id, item_key=item_key, allowed=True))
    session.commit()
    return {"saved": True, "user_id": user.id, "role": user.role, "changed_by": actor.id}

@app.delete("/admin/users/{user_id}")
def delete_user(user_id: int, _: Annotated[User, Depends(require_superadmin)], session: Annotated[Session, Depends(db)]):
    user = session.get(User, user_id)
    if not user: raise HTTPException(status_code=404, detail="الحساب غير موجود")
    if user.is_original or user.email == "1": raise HTTPException(status_code=403, detail="لا يمكن حذف السوبر أدمن الأصلي")
    session.delete(user); session.commit(); return {"deleted": True}

@app.get("/admin/items")
def admin_items(_: Annotated[User, Depends(require_admin)], session: Annotated[Session, Depends(db)]):
    return [{"key": item.key, "title": item.title, "enabled": item.enabled, "roles": {role: bool(session.scalar(select(RoleItem.enabled).where(RoleItem.role == role, RoleItem.item_key == item.key)) or False) for role in ROLE_ITEMS}} for item in session.scalars(select(Item).order_by(Item.id))]

@app.put("/admin/items/{item_key}")
def set_item_visibility(item_key: str, data: dict, _: Annotated[User, Depends(require_admin)], session: Annotated[Session, Depends(db)]):
    item = session.scalar(select(Item).where(Item.key == item_key))
    if not item: raise HTTPException(status_code=404, detail="العنصر غير موجود")
    role = data.get("role")
    if role in ROLE_ITEMS:
        role_item = session.scalar(select(RoleItem).where(RoleItem.role == role, RoleItem.item_key == item_key))
        if not role_item:
            role_item = RoleItem(role=role, item_key=item_key, enabled=bool(data.get("enabled", True)))
            session.add(role_item)
        else:
            role_item.enabled = bool(data.get("enabled", True))
    else:
        item.enabled = bool(data.get("enabled", True))
    session.commit(); return {"saved": True, "key": item.key, "role": role, "enabled": bool(data.get("enabled", True))}

@app.post("/admin/videos/presign")
def presign_video(data: PresignIn, _: Annotated[User, Depends(require_superadmin)]):
    client = r2_client()
    key = f"videos/{uuid4().hex}-{Path(data.filename).name}"
    upload_url = client.generate_presigned_url("put_object", Params={"Bucket": R2_BUCKET, "Key": key, "ContentType": data.content_type}, ExpiresIn=900)
    return {"key": key, "upload_url": upload_url, "expires_in": 900}

@app.post("/admin/videos/publish")
def publish_video(data: VideoPublishIn, _: Annotated[User, Depends(require_superadmin)], session: Annotated[Session, Depends(db)]):
    if not data.object_key.startswith("videos/"):
        raise HTTPException(status_code=400, detail="مسار R2 غير صالح")
    if data.access not in {"public", "vip"}:
        raise HTTPException(status_code=400, detail="نوع الوصول غير صالح")
    ensure_unique_video_title(VideoIn(language=data.language, title=data.title, access=data.access), session)
    video = Video(language=data.language, title=data.title, object_key=data.object_key, url="", access=data.access, published=True)
    session.add(video); session.commit(); session.refresh(video)
    return {"id": video.id, "language": video.language, "title": video.title, "access": video.access}

@app.delete("/admin/videos/{video_id}")
def delete_video(video_id: int, _: Annotated[User, Depends(require_superadmin)], session: Annotated[Session, Depends(db)]):
    video = session.get(Video, video_id)
    if not video: raise HTTPException(status_code=404, detail="الفيديو غير موجود")
    if not video.object_key:
        raise HTTPException(status_code=409, detail="الفيديو غير مربوط بملف في R2")
    try:
        r2_client().delete_object(Bucket=R2_BUCKET, Key=video.object_key)
    except Exception as error:
        raise HTTPException(status_code=502, detail="تعذر حذف ملف الفيديو من R2") from error
    session.delete(video); session.commit(); return {"deleted": True}

@app.get("/videos/{video_id}/url")
def video_url(video_id: int, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    video = session.get(Video, video_id)
    if not video or not video.published: raise HTTPException(status_code=404, detail="الفيديو غير موجود")
    if video.access == "vip" and user.role not in {"superadmin", "admin"}:
        raise HTTPException(status_code=403, detail="الفيديو غير متاح لهذا الحساب")
    if not can_access(user, "programming", None, session): raise HTTPException(status_code=403, detail="المحتوى غير مصرح به")
    if not video.object_key: raise HTTPException(status_code=503, detail="الفيديو غير مربوط بتخزين R2")
    signed_url = r2_client().generate_presigned_url("get_object", Params={"Bucket": R2_BUCKET, "Key": video.object_key}, ExpiresIn=300)
    return {"url": signed_url, "expires_in": 300}

@app.get("/progress")
def get_progress(user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    return [{"video_id": row.video_id, "position_seconds": row.position_seconds, "completed": row.completed, "updated_at": row.updated_at} for row in session.scalars(select(Progress).where(Progress.user_id == user.id))]

@app.put("/progress")
def save_progress(data: ProgressIn, user: Annotated[User, Depends(current_user)], session: Annotated[Session, Depends(db)]):
    row = session.scalar(select(Progress).where(Progress.user_id == user.id, Progress.video_id == data.video_id))
    if row:
        row.position_seconds = max(row.position_seconds, data.position_seconds)
        row.completed = row.completed or data.completed
    else:
        session.add(Progress(user_id=user.id, **data.model_dump()))
    session.commit(); return {"saved": True}