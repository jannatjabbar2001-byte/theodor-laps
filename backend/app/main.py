from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
import os
import re
from uuid import uuid4
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, ConfigDict, EmailStr
from sqlalchemy import Boolean, ForeignKey, Integer, String, create_engine, select, text
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
        return [origin] if origin else ["*"]
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

Base.metadata.create_all(engine)

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
            if ENVIRONMENT == "development"
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
app = FastAPI(title="الكون الشامل API", version="1.0.0")
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
def register(data: dict, session: Annotated[Session, Depends(db)]):
    username = str(data.get("username", "")).strip().lower()
    password = str(data.get("password", ""))
    if username == "1" or not username or len(password) < 8:
        raise HTTPException(status_code=400, detail="اسم المستخدم وكلمة المرور مطلوبان")
    if session.scalar(select(User).where(User.email == username)):
        raise HTTPException(status_code=409, detail="اسم المستخدم مستخدم من قبل")
    user = User(email=username, password_hash=pwd.hash(password), role="user")
    session.add(user)
    session.commit()
    session.refresh(user)
    return user

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