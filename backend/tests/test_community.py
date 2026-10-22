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

    def setUp(self):
        with main.SessionLocal() as session:
            session.execute(main.delete(main.CommunityMessage))
            session.execute(main.delete(main.CommunityMembership))
            session.execute(main.delete(main.CommunityConversation))
            session.execute(main.delete(main.CommunityProfile))
            restricted = session.scalar(
                main.select(main.User).where(main.User.email == "community-restricted@example.test")
            )
            if restricted:
                session.execute(main.delete(main.Permission).where(main.Permission.user_id == restricted.id))
                session.execute(main.delete(main.User).where(main.User.id == restricted.id))
            session.execute(main.delete(main.RoleItem).where(main.RoleItem.role == "restricted"))
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
            self.assertIsNotNone(sent["expires_at"])

    def test_private_access_and_unread_cursor(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            reader = session.get(main.User, self.user_ids[1])
            outsider = session.get(main.User, self.user_ids[2])
            conversation = main.create_community_conversation(
                main.CommunityConversationIn(user_id=reader.id), sender, session
            )
            conversation_id = conversation["id"]
            private_message = main.send_private_community_message(
                conversation_id, main.CommunityMessageIn(body="رسالة خاصة"), sender, session
            )
            self.assertIsNone(private_message["expires_at"])
            with self.assertRaises(HTTPException) as error:
                main.require_conversation_member(conversation_id, outsider, session)
            self.assertEqual(error.exception.status_code, 404)
            self.assertEqual(main.list_community_conversations(reader, session)[0]["unread_count"], 1)
            received = main.private_community_messages(conversation_id, reader, session)
            self.assertEqual(received[0]["body"], "رسالة خاصة")
            self.assertEqual(main.list_community_conversations(reader, session)[0]["unread_count"], 0)

    def test_private_conversation_can_be_hidden_for_one_user(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            recipient = session.get(main.User, self.user_ids[1])
            conversation = main.create_community_conversation(
                main.CommunityConversationIn(user_id=recipient.id), sender, session
            )
            conversation_id = conversation["id"]
            original = main.send_private_community_message(
                conversation_id,
                main.CommunityMessageIn(body="تاريخ محفوظ للطرف الآخر"),
                sender,
                session,
            )

            hidden = main.delete_community_conversation(
                conversation_id, recipient, session, "me"
            )
            self.assertEqual(hidden, {"deleted_for": "me"})
            self.assertEqual(main.list_community_conversations(recipient, session), [])
            self.assertEqual(len(main.list_community_conversations(sender, session)), 1)
            self.assertEqual(
                main.private_community_messages(conversation_id, recipient, session),
                [],
            )
            self.assertEqual(
                main.private_community_messages(conversation_id, sender, session)[0]["id"],
                original["id"],
            )
            with self.assertRaises(HTTPException) as error:
                main.send_private_community_message(
                    conversation_id,
                    main.CommunityMessageIn(body="رد مخفي", reply_to_id=original["id"]),
                    recipient,
                    session,
                )
            self.assertEqual(error.exception.status_code, 404)

            new_message = main.send_private_community_message(
                conversation_id,
                main.CommunityMessageIn(body="رسالة بعد الإخفاء"),
                sender,
                session,
            )
            visible = main.private_community_messages(conversation_id, recipient, session)
            self.assertEqual([message["id"] for message in visible], [new_message["id"]])
            self.assertEqual(len(main.list_community_conversations(recipient, session)), 1)

    def test_private_conversation_can_be_deleted_for_everyone(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            recipient = session.get(main.User, self.user_ids[1])
            conversation = main.create_community_conversation(
                main.CommunityConversationIn(user_id=recipient.id), sender, session
            )
            conversation_id = conversation["id"]
            message = main.send_private_community_message(
                conversation_id,
                main.CommunityMessageIn(body="يُحذف للجميع"),
                sender,
                session,
            )
            outsider = session.get(main.User, self.user_ids[2])
            with self.assertRaises(HTTPException) as error:
                main.delete_community_conversation(
                    conversation_id, outsider, session, "everyone"
                )
            self.assertEqual(error.exception.status_code, 404)
            self.assertIsNotNone(session.get(main.CommunityConversation, conversation_id))
            deleted = main.delete_community_conversation(
                conversation_id, recipient, session, "everyone"
            )
            self.assertEqual(deleted, {"deleted_for": "everyone"})
            self.assertIsNone(session.get(main.CommunityConversation, conversation_id))
            self.assertIsNone(session.get(main.CommunityMessage, message["id"]))
            with self.assertRaises(HTTPException) as error:
                main.private_community_messages(conversation_id, sender, session)
            self.assertEqual(error.exception.status_code, 404)

    def test_replies_stay_inside_their_conversation(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            recipient = session.get(main.User, self.user_ids[1])
            public_root = main.send_public_community_message(
                main.CommunityMessageIn(body="رسالة عامة أصلية"), sender, session
            )
            private_conversation = main.create_community_conversation(
                main.CommunityConversationIn(user_id=recipient.id), sender, session
            )
            private_root = main.send_private_community_message(
                private_conversation["id"],
                main.CommunityMessageIn(body="رسالة خاصة أصلية"),
                sender,
                session,
            )
            with self.assertRaises(HTTPException) as error:
                main.send_public_community_message(
                    main.CommunityMessageIn(body="رد عام", reply_to_id=private_root["id"]),
                    sender,
                    session,
                )
            self.assertEqual(error.exception.status_code, 404)
            reply = main.send_public_community_message(
                main.CommunityMessageIn(body="رد عام صحيح", reply_to_id=public_root["id"]),
                sender,
                session,
            )
            self.assertEqual(reply["reply_to"]["id"], public_root["id"])

    def test_expiry_cleanup_only_deletes_expired_public_messages(self):
        with main.SessionLocal() as session:
            sender = session.get(main.User, self.user_ids[0])
            recipient = session.get(main.User, self.user_ids[1])
            conversation = main.create_community_conversation(
                main.CommunityConversationIn(user_id=recipient.id), sender, session
            )
            expired = main.CommunityMessage(
                sender_id=sender.id,
                body="expired public test",
                created_at=datetime.now(timezone.utc) - timedelta(hours=25),
                expires_at=datetime.now(timezone.utc) - timedelta(hours=1),
            )
            current = main.CommunityMessage(
                sender_id=sender.id,
                body="current public test",
                expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
            )
            private = main.CommunityMessage(
                sender_id=sender.id,
                conversation_id=conversation["id"],
                body="permanent private test",
            )
            session.add_all([expired, current, private])
            session.flush()
            expired_id, current_id, private_id = expired.id, current.id, private.id
            result = session.execute(main.expired_public_messages_statement())
            session.commit()
            remaining = set(session.scalars(
                main.select(main.CommunityMessage.id).where(
                    main.CommunityMessage.id.in_([expired_id, current_id, private_id])
                )
            ).all())
            self.assertEqual(result.rowcount, 1)
            self.assertEqual(remaining, {current_id, private_id})

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