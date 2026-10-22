import asyncio
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
TEST_DIRECTORY = tempfile.TemporaryDirectory(prefix="theodore-community-tests-")
TEST_DATABASE = Path(TEST_DIRECTORY.name) / "community.db"
os.environ["ENVIRONMENT"] = "development"
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DATABASE.as_posix()}"
os.environ["JWT_SECRET"] = "community-test-secret-that-is-not-used-outside-tests"
os.environ["FRONTEND_ORIGIN"] = ""
sys.path.insert(0, str(BACKEND_ROOT))

from fastapi import HTTPException
from app import main


class _AvatarUpload:
    content_type = "image/png"

    async def read(self, limit):
        return b"\x89PNG\r\n\x1a\ncommunity-test-image"


class CommunityApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original_media = main.MEDIA
        main.MEDIA = Path(TEST_DIRECTORY.name) / "media"
        cls.user_ids = []
        with main.SessionLocal() as session:
            for index in range(3):
                user = main.User(
                    email=f"community-test-{index}@example.test",
                    password_hash="unused-in-api-tests",
                    role="user",
                )
                session.add(user)
                session.flush()
                session.add(main.Permission(user_id=user.id, item_key="community", allowed=True))
                cls.user_ids.append(user.id)
            session.commit()

    @classmethod
    def tearDownClass(cls):
        main.engine.dispose()
        main.MEDIA = cls.original_media
        TEST_DIRECTORY.cleanup()

    def token(self, user_id):
        return main.jwt.encode(
            {"sub": str(user_id), "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
            main.SECRET,
            algorithm="HS256",
        )

    def test_public_messages_are_shared_without_exposing_email(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            reader = main.current_user(self.token(self.user_ids[1]), session)
            sent = main.send_public_community_message(
                main.CommunityMessageIn(body="رسالة للمجتمع"), sender, session
            )
            received = main.public_community_messages(reader, session)
            self.assertEqual(sent["body"], received[-1]["body"])
            self.assertNotIn("email", received[-1]["sender"])

    def test_private_access_and_unread_cursor(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            reader = session.get(main.User, self.user_ids[1])
            outsider = session.get(main.User, self.user_ids[2])
            conversation = main.create_community_conversation(
                main.CommunityConversationIn(user_id=reader.id), sender, session
            )
            conversation_id = conversation["id"]
            main.send_private_community_message(
                conversation_id, main.CommunityMessageIn(body="رسالة خاصة"), sender, session
            )
            with self.assertRaises(HTTPException) as error:
                main.require_conversation_member(conversation_id, outsider, session)
            self.assertEqual(error.exception.status_code, 404)
            self.assertEqual(main.list_community_conversations(reader, session)[0]["unread_count"], 1)
            received = main.private_community_messages(conversation_id, reader, session)
            self.assertEqual(received[0]["body"], "رسالة خاصة")
            self.assertEqual(main.list_community_conversations(reader, session)[0]["unread_count"], 0)

    def test_member_search_returns_only_public_profile_fields(self):
        with main.SessionLocal() as session:
            target = session.get(main.User, self.user_ids[1])
            viewer = session.get(main.User, self.user_ids[0])
            main.update_community_profile(
                main.CommunityProfileIn(display_name="عضو التجربة"), target, session
            )
            result = main.community_users("التجربة", 40, viewer, session)
            self.assertEqual(result[0]["display_name"], "عضو التجربة")
            self.assertNotIn("email", result[0])

    def test_directory_hides_users_without_community_permission(self):
        with main.SessionLocal() as session:
            restricted = main.User(
                email="community-restricted@example.test",
                password_hash="unused-in-api-tests",
                role="restricted",
            )
            session.add(restricted)
            session.flush()
            session.add_all([
                main.Permission(user_id=restricted.id, item_key="community", allowed=True),
                main.RoleItem(role="restricted", item_key="community", enabled=False),
            ])
            session.commit()
            viewer = session.get(main.User, self.user_ids[0])
            result = main.community_users("", 100, viewer, session)
            self.assertNotIn(restricted.id, {member["id"] for member in result})

    def test_avatar_is_stored_and_served_to_community_members(self):
        with main.SessionLocal() as session:
            user = session.get(main.User, self.user_ids[0])
            profile = main.CommunityProfile(user_id=user.id, display_name="صاحب الصورة")
            session.add(profile)
            session.flush()
            asyncio.run(main.store_community_avatar(user.id, _AvatarUpload(), profile, session))
            avatar = main.get_community_avatar(user.id, user, session)
            self.assertTrue(Path(avatar.path).is_file())
            self.assertIn(f"/community/avatars/{user.id}?v=", main.community_user_data(user, session)["avatar_url"])


if __name__ == "__main__":
    unittest.main()