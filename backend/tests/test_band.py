import asyncio
import uuid
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.band import auth_api
from app.band.account_jobs import _delete_account
from app.band.bands_api import (
    accept_invitation,
    create_band,
    create_invitation,
    list_invitations,
    transfer_ownership,
    update_band,
)
from app.band.collaboration_api import create_post, list_posts, update_post
from app.band.database import Base, SessionFactory, engine
from app.band.errors import BandAPIError
from app.band.media_api import validate_upload
from app.band.models import (
    AppleIdentity,
    Asset,
    AssetKind,
    AssetStatus,
    AuthSession,
    Band,
    BandCardKind,
    BandCardSize,
    BandMembership,
    BandRole,
    Comment,
    Post,
    Project,
    User,
    utcnow,
)
from app.band.schemas import (
    AppleAuthRequest,
    BandCreate,
    BandUpdate,
    OwnershipTransfer,
    PostCreate,
    PostUpdate,
    UploadRequest,
)
from app.band.security import (
    AppleClaims,
    AppleTokenExchange,
    create_session_tokens,
    rotate_refresh_token,
)
from app.band.service import membership_for
from app.main import app


def run(coroutine):
    return asyncio.run(coroutine)


async def reset_database() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)


@pytest.fixture(autouse=True)
def clean_database():
    run(reset_database())


def profile_user(name: str) -> User:
    return User(
        username=name,
        display_name=name.title(),
        age_gate_passed_at=utcnow(),
        terms_accepted_at=utcnow(),
        terms_version="test",
    )


class FakeAppleIdentityProvider:
    def __init__(self, subject: str) -> None:
        self.subject = subject

    def verify_identity_token(self, identity_token: str, raw_nonce: str) -> AppleClaims:
        assert identity_token == "identity-token-from-apple"
        assert raw_nonce == "nonce-used-for-test"
        return AppleClaims(subject=self.subject, email="musician@example.com")

    async def exchange_code(self, authorization_code: str) -> AppleTokenExchange:
        assert authorization_code == "authorization-code"
        return AppleTokenExchange(
            refresh_token="apple-refresh-token",
            access_token="apple-access-token",
        )


def apple_auth_request() -> AppleAuthRequest:
    return AppleAuthRequest(
        identity_token="identity-token-from-apple",
        authorization_code="authorization-code",
        nonce="nonce-used-for-test",
        display_name="  New Musician  ",
    )


def test_openapi_publishes_apple_authentication_contract():
    operation = app.openapi()["paths"]["/v1/auth/apple"]["post"]
    assert operation["responses"]["200"]["content"]["application/json"]

    response = TestClient(app).post("/v1/auth/apple", json={})
    assert response.status_code == 422
    assert response.json()["detail"]


def test_apple_authentication_requires_profile_for_new_user(monkeypatch):
    monkeypatch.setattr(
        auth_api,
        "apple_identity_provider",
        FakeAppleIdentityProvider("new-apple-subject"),
    )

    async def scenario():
        async with SessionFactory() as session:
            tokens = await auth_api.authenticate_with_apple(apple_auth_request(), session)
            identity = await session.scalar(
                select(AppleIdentity).where(AppleIdentity.subject == "new-apple-subject")
            )
            user = await session.get(User, identity.user_id)
            assert tokens.profile_required is True
            assert len(tokens.access_token) > 20
            assert len(tokens.refresh_token) > 32
            assert user.display_name == "New Musician"

    run(scenario())


def test_apple_authentication_returns_existing_user_to_band(monkeypatch):
    monkeypatch.setattr(
        auth_api,
        "apple_identity_provider",
        FakeAppleIdentityProvider("returning-apple-subject"),
    )

    async def scenario():
        async with SessionFactory() as session:
            returning = profile_user("returning")
            session.add(returning)
            await session.flush()
            session.add(
                AppleIdentity(
                    user_id=returning.id,
                    subject="returning-apple-subject",
                    email="musician@example.com",
                )
            )
            await session.commit()

            tokens = await auth_api.authenticate_with_apple(apple_auth_request(), session)
            users = list((await session.scalars(select(User))).all())
            assert tokens.profile_required is False
            assert users == [returning]

    run(scenario())


def test_owned_band_limit_and_cross_band_access():
    async def scenario():
        async with SessionFactory() as session:
            owner = profile_user("owner")
            outsider = profile_user("outsider")
            session.add_all([owner, outsider])
            await session.commit()

            created = []
            for index in range(3):
                created.append(
                    await create_band(
                        BandCreate(name=f"Band {index}", description=""), owner, session
                    )
                )
            with pytest.raises(BandAPIError) as limit:
                await create_band(BandCreate(name="Fourth", description=""), owner, session)
            assert limit.value.code == "owned_band_limit"

            with pytest.raises(BandAPIError) as denied:
                await membership_for(session, created[0].id, outsider.id)
            assert denied.value.code == "band_access_denied"

    run(scenario())


def test_ownership_transfer_is_atomic_and_uses_one_owner():
    async def scenario():
        async with SessionFactory() as session:
            owner = profile_user("owner")
            target = profile_user("target")
            session.add_all([owner, target])
            await session.flush()
            band = Band(name="The Band", owner_user_id=owner.id)
            session.add(band)
            await session.flush()
            session.add_all(
                [
                    BandMembership(band_id=band.id, user_id=owner.id, role=BandRole.owner),
                    BandMembership(band_id=band.id, user_id=target.id, role=BandRole.member),
                ]
            )
            await session.commit()

            await transfer_ownership(
                band.id, OwnershipTransfer(user_id=target.id), owner, session
            )
            memberships = list(
                (
                    await session.scalars(
                        select(BandMembership).where(BandMembership.band_id == band.id)
                    )
                ).all()
            )
            assert sum(item.role == BandRole.owner for item in memberships) == 1
            assert (await session.get(Band, band.id)).owner_user_id == target.id

    run(scenario())


def test_invitation_is_hashed_single_use_and_list_does_not_expose_token():
    async def scenario():
        async with SessionFactory() as session:
            owner = profile_user("owner")
            invitee = profile_user("invitee")
            session.add_all([owner, invitee])
            await session.commit()
            band = await create_band(BandCreate(name="Invite Band", description=""), owner, session)
            response = await create_invitation(band.id, owner, session)
            token = response.url.rsplit("/", 1)[-1]
            pending = await list_invitations(band.id, owner, session)
            assert len(pending) == 1
            assert token not in pending[0].model_dump_json()

            joined = await accept_invitation(token, invitee, session)
            assert joined.role == BandRole.member
            with pytest.raises(BandAPIError) as reused:
                await accept_invitation(token, invitee, session)
            assert reused.value.code == "invitation_expired"

    run(scenario())


def test_refresh_rotation_revokes_family_when_an_old_token_is_reused():
    async def scenario():
        async with SessionFactory() as session:
            user = profile_user("listener")
            session.add(user)
            await session.flush()
            _, first_refresh, _, _, first_record = await create_session_tokens(session, user.id)
            family_id = first_record.family_id
            await session.commit()

            _, second_refresh, _, _ = await rotate_refresh_token(session, first_refresh)
            assert second_refresh != first_refresh
            with pytest.raises(BandAPIError) as reused:
                await rotate_refresh_token(session, first_refresh)
            assert reused.value.code == "refresh_token_reused"
            family = list(
                (
                    await session.scalars(
                        select(AuthSession).where(AuthSession.family_id == family_id)
                    )
                ).all()
            )
            assert len(family) == 2
            assert all(item.revoked_at is not None for item in family)

    run(scenario())


def test_media_limits_and_project_only_rule():
    band_id = uuid.uuid4()
    with pytest.raises(BandAPIError) as general_audio:
        validate_upload(
            UploadRequest(
                band_id=band_id,
                kind=AssetKind.audio,
                filename="take.m4a",
                content_type="audio/mp4",
                byte_size=1024,
            )
        )
    assert general_audio.value.code == "project_media_required"

    with pytest.raises(BandAPIError) as image_limit:
        validate_upload(
            UploadRequest(
                band_id=band_id,
                kind=AssetKind.image,
                filename="photo.jpg",
                content_type="image/jpeg",
                byte_size=20 * 1024 * 1024 + 1,
            )
        )
    assert image_limit.value.code == "file_too_large"


def test_band_appearance_validates_assets_color_and_feature(monkeypatch):
    monkeypatch.setattr("app.band.bands_api.band_queue.enqueue", lambda *args: None)

    async def scenario():
        async with SessionFactory() as session:
            owner = profile_user("owner")
            member = profile_user("member")
            session.add_all([owner, member])
            await session.commit()
            response = await create_band(
                BandCreate(name="Mood", description=""), owner, session
            )
            band = await session.get(Band, response.id)
            session.add(
                BandMembership(
                    band_id=band.id, user_id=member.id, role=BandRole.member
                )
            )
            project = Project(
                band_id=band.id,
                title="First EP",
                created_by_user_id=owner.id,
            )
            old_logo = Asset(
                band_id=band.id,
                uploaded_by_user_id=owner.id,
                kind=AssetKind.image,
                status=AssetStatus.ready,
                storage_key=f"bands/{band.id}/assets/{uuid.uuid4()}/original",
                original_filename="old.jpg",
                content_type="image/jpeg",
                declared_byte_size=100,
                byte_size=100,
                upload_expires_at=utcnow() + timedelta(hours=1),
            )
            new_logo = Asset(
                band_id=band.id,
                uploaded_by_user_id=owner.id,
                kind=AssetKind.image,
                status=AssetStatus.ready,
                storage_key=f"bands/{band.id}/assets/{uuid.uuid4()}/original",
                original_filename="new.jpg",
                content_type="image/jpeg",
                declared_byte_size=100,
                byte_size=100,
                upload_expires_at=utcnow() + timedelta(hours=1),
            )
            session.add_all([project, old_logo, new_logo])
            await session.flush()
            band.image_asset_id = old_logo.id
            band.used_bytes = 200
            await session.commit()

            updated = await update_band(
                band.id,
                BandUpdate(
                    image_asset_id=new_logo.id,
                    accent_color_hex="#a1b2c3",
                    featured_project_id=project.id,
                ),
                owner,
                session,
            )
            assert updated.image_asset_id == new_logo.id
            assert updated.accent_color_hex == "#A1B2C3"
            assert updated.featured_project_id == project.id
            assert (await session.get(Asset, old_logo.id)).deleted_at is not None
            assert (await session.get(Band, band.id)).used_bytes == 100

            with pytest.raises(BandAPIError) as color:
                await update_band(
                    band.id,
                    BandUpdate(accent_color_hex="#XYZ123"),
                    owner,
                    session,
                )
            assert color.value.code == "invalid_accent_color"

            with pytest.raises(BandAPIError) as denied:
                await update_band(
                    band.id,
                    BandUpdate(accent_color_hex="#112233"),
                    member,
                    session,
                )
            assert denied.value.code == "permission_denied"

    run(scenario())


def test_mood_board_card_rules_sizing_pins_and_project_filtering():
    async def scenario():
        async with SessionFactory() as session:
            owner = profile_user("owner")
            member = profile_user("member")
            session.add_all([owner, member])
            await session.commit()
            response = await create_band(
                BandCreate(name="Board", description=""), owner, session
            )
            band = await session.get(Band, response.id)
            session.add(
                BandMembership(
                    band_id=band.id, user_id=member.id, role=BandRole.member
                )
            )
            project = Project(
                band_id=band.id, title="Open Skies", created_by_user_id=owner.id
            )
            images = [
                Asset(
                    band_id=band.id,
                    uploaded_by_user_id=owner.id,
                    kind=AssetKind.image,
                    status=AssetStatus.ready,
                    storage_key=f"bands/{band.id}/assets/{uuid.uuid4()}/original",
                    original_filename=f"image-{index}.jpg",
                    content_type="image/jpeg",
                    declared_byte_size=100,
                    byte_size=100,
                    upload_expires_at=utcnow() + timedelta(hours=1),
                )
                for index in range(2)
            ]
            session.add_all([project, *images])
            await session.commit()

            note = await create_post(
                band.id,
                PostCreate(card_kind=BandCardKind.note, body="Warm and hazy"),
                owner,
                session,
            )
            image = await create_post(
                band.id,
                PostCreate(
                    card_kind=BandCardKind.image,
                    body="Visual direction",
                    asset_ids=[item.id for item in images],
                ),
                owner,
                session,
            )
            link = await create_post(
                band.id,
                PostCreate(
                    card_kind=BandCardKind.link,
                    external_url="https://example.com/reference",
                ),
                owner,
                session,
            )
            project_card = await create_post(
                band.id,
                PostCreate(
                    card_kind=BandCardKind.project,
                    referenced_project_id=project.id,
                ),
                owner,
                session,
            )
            await create_post(
                band.id,
                PostCreate(project_id=project.id, body="Project-only activity"),
                owner,
                session,
            )
            assert note.card_size == BandCardSize.compact
            assert image.card_size == BandCardSize.wide
            assert link.card_size == BandCardSize.compact
            assert project_card.card_size == BandCardSize.wide

            await update_post(
                band.id,
                note.id,
                PostUpdate(is_pinned=True),
                owner,
                session,
            )
            await update_post(
                band.id,
                link.id,
                PostUpdate(is_pinned=True),
                owner,
                session,
            )
            page = await list_posts(
                band.id,
                project_id=None,
                surface="board",
                cursor=None,
                user=owner,
                session=session,
            )
            assert [item.id for item in page.items[:2]] == [link.id, note.id]
            assert len(page.items) == 4

            with pytest.raises(BandAPIError) as denied:
                await update_post(
                    band.id,
                    image.id,
                    PostUpdate(is_pinned=True),
                    member,
                    session,
                )
            assert denied.value.code == "permission_denied"

            with pytest.raises(BandAPIError) as invalid:
                await create_post(
                    band.id,
                    PostCreate(card_kind=BandCardKind.image, body="No image"),
                    owner,
                    session,
                )
            assert invalid.value.code == "invalid_image_card"

    run(scenario())


def test_account_deletion_removes_personal_content_and_keeps_anonymous_tombstone():
    async def scenario():
        deleting_id: uuid.UUID
        band_id: uuid.UUID
        async with SessionFactory() as session:
            owner = profile_user("owner")
            deleting = profile_user("leaving")
            session.add_all([owner, deleting])
            await session.flush()
            deleting_id = deleting.id
            session.add(AppleIdentity(user_id=deleting.id, subject="apple-subject"))
            band = Band(name="Shared", owner_user_id=owner.id, used_bytes=100)
            session.add(band)
            await session.flush()
            band_id = band.id
            session.add_all(
                [
                    BandMembership(band_id=band.id, user_id=owner.id, role=BandRole.owner),
                    BandMembership(band_id=band.id, user_id=deleting.id, role=BandRole.member),
                ]
            )
            asset = Asset(
                band_id=band.id,
                uploaded_by_user_id=deleting.id,
                kind=AssetKind.image,
                status=AssetStatus.ready,
                storage_key=f"bands/{band.id}/assets/{uuid.uuid4()}/original",
                original_filename="photo.jpg",
                content_type="image/jpeg",
                declared_byte_size=100,
                byte_size=100,
                upload_expires_at=utcnow() + timedelta(hours=1),
            )
            post = Post(band_id=band.id, author_user_id=deleting.id, body="personal")
            session.add_all([asset, post])
            await session.flush()
            session.add(Comment(post_id=post.id, author_user_id=deleting.id, body="personal"))
            deleting.deletion_requested_at = utcnow()
            await session.commit()

        await _delete_account(deleting_id)

        async with SessionFactory() as session:
            tombstone = await session.get(User, deleting_id)
            assert tombstone is not None
            assert tombstone.username is None and tombstone.display_name is None
            assert await session.get(AppleIdentity, deleting_id) is None
            assert not list(
                (
                    await session.scalars(
                        select(BandMembership).where(BandMembership.user_id == deleting_id)
                    )
                ).all()
            )
            assert not list(
                (await session.scalars(select(Post).where(Post.author_user_id == deleting_id))).all()
            )
            assert (await session.get(Band, band_id)).used_bytes == 0

    run(scenario())
