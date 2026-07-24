import uuid

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.content import validate_external_url, validate_text
from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import (
    Asset,
    AssetKind,
    AssetStatus,
    Band,
    BandCardKind,
    BandCardSize,
    BandMembership,
    BandRole,
    Comment,
    MembershipStatus,
    Mention,
    NotificationKind,
    Post,
    PostAttachment,
    Project,
    ProjectTrack,
    Reaction,
    ReactionKind,
    TrackTake,
    User,
    UserBlock,
    utcnow,
)
from app.band.schemas import (
    AssetResponse,
    CommentCreate,
    CommentResponse,
    Page,
    PostCreate,
    PostResponse,
    PostReactionSummary,
    PostUpdate,
    ProjectCreate,
    ProjectResponse,
    ProjectUpdate,
    ReactionRequest,
    TakeCreate,
    TakeResponse,
    TrackCreate,
    TrackResponse,
)
from app.band.security import current_user
from app.band.service import (
    blocked_between,
    create_notification,
    decode_cursor,
    editable_membership,
    encode_cursor,
    membership_for,
)


router = APIRouter(prefix="/v1", tags=["Band collaboration"])
PAGE_SIZE = 25


async def require_project(
    session: AsyncSession, project_id: uuid.UUID, band_id: uuid.UUID
) -> Project:
    project = await session.get(Project, project_id)
    if project is None or project.band_id != band_id:
        raise BandAPIError("project_not_found", "This project no longer exists.", 404)
    return project


@router.get("/bands/{band_id}/projects", response_model=Page[ProjectResponse])
async def list_projects(
    band_id: uuid.UUID,
    include_archived: bool = False,
    cursor: str | None = Query(default=None),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Page[ProjectResponse]:
    await membership_for(session, band_id, user.id)
    offset = decode_cursor(cursor)
    query = select(Project).where(Project.band_id == band_id)
    if not include_archived:
        query = query.where(Project.archived_at.is_(None))
    projects = list(
        (
            await session.scalars(
                query.order_by(Project.updated_at.desc()).offset(offset).limit(PAGE_SIZE + 1)
            )
        ).all()
    )
    has_more = len(projects) > PAGE_SIZE
    return Page(
        items=[ProjectResponse.model_validate(item) for item in projects[:PAGE_SIZE]],
        next_cursor=encode_cursor(offset + PAGE_SIZE) if has_more else None,
    )


@router.post("/bands/{band_id}/projects", response_model=ProjectResponse, status_code=201)
async def create_project(
    band_id: uuid.UUID,
    body: ProjectCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ProjectResponse:
    await editable_membership(session, band_id, user.id)
    project = Project(
        band_id=band_id,
        title=validate_text(body.title, field="title", maximum=80),
        description=validate_text(
            body.description, field="description", maximum=1000, allow_empty=True
        ),
        musical_key=body.musical_key,
        bpm=body.bpm,
        time_signature=body.time_signature,
        status=body.status,
        created_by_user_id=user.id,
    )
    session.add(project)
    await session.commit()
    return ProjectResponse.model_validate(project)


@router.get("/bands/{band_id}/projects/{project_id}", response_model=ProjectResponse)
async def get_project(
    band_id: uuid.UUID,
    project_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ProjectResponse:
    await membership_for(session, band_id, user.id)
    return ProjectResponse.model_validate(await require_project(session, project_id, band_id))


@router.patch("/bands/{band_id}/projects/{project_id}", response_model=ProjectResponse)
async def update_project(
    band_id: uuid.UUID,
    project_id: uuid.UUID,
    body: ProjectUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> ProjectResponse:
    _, membership = await editable_membership(session, band_id, user.id)
    project = await require_project(session, project_id, band_id)
    if membership.role == BandRole.member and project.created_by_user_id != user.id:
        raise BandAPIError("permission_denied", "You can’t edit this project.", 403)
    if project.archived_at and body.archived is not False:
        raise BandAPIError("project_archived", "Restore this project before editing it.", 409)
    if body.title is not None:
        project.title = validate_text(body.title, field="title", maximum=80)
    if body.description is not None:
        project.description = validate_text(
            body.description, field="description", maximum=1000, allow_empty=True
        )
    for name in ("musical_key", "bpm", "time_signature", "status"):
        value = getattr(body, name)
        if value is not None:
            setattr(project, name, value)
    if body.archived is not None:
        project.archived_at = utcnow() if body.archived else None
        if body.archived:
            band = await session.get(Band, band_id)
            if band and band.featured_project_id == project.id:
                band.featured_project_id = None
    await session.commit()
    return ProjectResponse.model_validate(project)


@router.get("/bands/{band_id}/projects/{project_id}/tracks", response_model=list[TrackResponse])
async def list_tracks(
    band_id: uuid.UUID,
    project_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TrackResponse]:
    await membership_for(session, band_id, user.id)
    await require_project(session, project_id, band_id)
    tracks = list(
        (
            await session.scalars(
                select(ProjectTrack)
                .where(ProjectTrack.project_id == project_id)
                .order_by(ProjectTrack.created_at)
            )
        ).all()
    )
    return [TrackResponse.model_validate(track) for track in tracks]


@router.post(
    "/bands/{band_id}/projects/{project_id}/tracks",
    response_model=TrackResponse,
    status_code=201,
)
async def create_track(
    band_id: uuid.UUID,
    project_id: uuid.UUID,
    body: TrackCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> TrackResponse:
    await editable_membership(session, band_id, user.id)
    project = await require_project(session, project_id, band_id)
    if project.archived_at:
        raise BandAPIError("project_archived", "Restore this project before adding tracks.", 409)
    track = ProjectTrack(
        project_id=project_id,
        name=validate_text(body.name, field="name", maximum=80),
        part_kind=body.part_kind,
        custom_part_label=body.custom_part_label,
        created_by_user_id=user.id,
    )
    session.add(track)
    await session.commit()
    return TrackResponse.model_validate(track)


@router.get("/bands/{band_id}/tracks/{track_id}/takes", response_model=list[TakeResponse])
async def list_takes(
    band_id: uuid.UUID,
    track_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TakeResponse]:
    await membership_for(session, band_id, user.id)
    track = await session.get(ProjectTrack, track_id)
    if track is None:
        raise BandAPIError("track_not_found", "This track no longer exists.", 404)
    await require_project(session, track.project_id, band_id)
    takes = list(
        (
            await session.scalars(
                select(TrackTake)
                .where(
                    TrackTake.project_track_id == track.id,
                    TrackTake.deleted_at.is_(None),
                )
                .order_by(TrackTake.created_at.desc())
            )
        ).all()
    )
    return [TakeResponse.model_validate(take) for take in takes]


@router.post(
    "/bands/{band_id}/tracks/{track_id}/takes",
    response_model=TakeResponse,
    status_code=201,
)
async def create_take(
    band_id: uuid.UUID,
    track_id: uuid.UUID,
    body: TakeCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> TakeResponse:
    await editable_membership(session, band_id, user.id)
    track = await session.get(ProjectTrack, track_id)
    if track is None:
        raise BandAPIError("track_not_found", "This track no longer exists.", 404)
    project = await require_project(session, track.project_id, band_id)
    if project.archived_at:
        raise BandAPIError("project_archived", "Restore this project before adding takes.", 409)
    asset = await session.get(Asset, body.asset_id)
    if (
        asset is None
        or asset.band_id != band_id
        or asset.project_id != project.id
        or asset.kind != AssetKind.audio
        or asset.status != AssetStatus.ready
    ):
        raise BandAPIError("asset_not_ready", "Choose a ready audio upload.", 409)
    existing = await session.scalar(select(TrackTake).where(TrackTake.asset_id == asset.id))
    if existing:
        return TakeResponse.model_validate(existing)
    take = TrackTake(
        project_track_id=track.id,
        asset_id=asset.id,
        take_number=body.take_number,
        version_label=body.version_label,
        start_offset_milliseconds=body.start_offset_milliseconds,
        notes=validate_text(body.notes, field="notes", maximum=1000, allow_empty=True),
        created_by_user_id=user.id,
    )
    session.add(take)
    await session.flush()
    post = Post(
        band_id=band_id,
        project_id=project.id,
        author_user_id=user.id,
        body=f"{track.name} · Take {body.take_number}",
    )
    session.add(post)
    await session.flush()
    session.add(PostAttachment(post_id=post.id, asset_id=asset.id, display_order=0))
    member_ids = list(
        (
            await session.scalars(
                select(BandMembership.user_id).where(
                    BandMembership.band_id == band_id,
                    BandMembership.status == MembershipStatus.active,
                )
            )
        ).all()
    )
    for member_id in member_ids:
        await create_notification(
            session,
            recipient_user_id=member_id,
            band_id=band_id,
            actor_user_id=user.id,
            kind=NotificationKind.new_take,
            entity_type="take",
            entity_id=take.id,
            dedupe_key=f"take:{take.id}",
            send_push=True,
        )
    await session.commit()
    return TakeResponse.model_validate(take)


async def validate_mentions(
    session: AsyncSession,
    *,
    band_id: uuid.UUID,
    author_user_id: uuid.UUID,
    mentioned_user_ids: list[uuid.UUID],
) -> list[uuid.UUID]:
    unique = list(dict.fromkeys(mentioned_user_ids))
    if not unique:
        return []
    active = set(
        (
            await session.scalars(
                select(BandMembership.user_id).where(
                    BandMembership.band_id == band_id,
                    BandMembership.user_id.in_(unique),
                    BandMembership.status == MembershipStatus.active,
                )
            )
        ).all()
    )
    if active != set(unique):
        raise BandAPIError("invalid_mention", "Mention only active Band members.")
    for mentioned_id in unique:
        if await blocked_between(session, author_user_id, mentioned_id):
            raise BandAPIError("blocked_interaction", "This mention can’t be sent.", 409)
    return unique


async def build_post_response(
    session: AsyncSession, post: Post, current_user_id: uuid.UUID
) -> PostResponse:
    author = await session.get(User, post.author_user_id)
    assets = list(
        (
            await session.scalars(
                select(Asset)
                .join(PostAttachment, PostAttachment.asset_id == Asset.id)
                .where(PostAttachment.post_id == post.id)
                .order_by(PostAttachment.display_order)
            )
        ).all()
    )
    post_reactions = list(
        (
            await session.scalars(
                select(Reaction).where(Reaction.post_id == post.id)
            )
        ).all()
    )
    reaction_counts: dict[ReactionKind, int] = {}
    current_user_reactions: set[ReactionKind] = set()
    for reaction in post_reactions:
        reaction_counts[reaction.kind] = reaction_counts.get(reaction.kind, 0) + 1
        if reaction.user_id == current_user_id:
            current_user_reactions.add(reaction.kind)
    return PostResponse(
        id=post.id,
        band_id=post.band_id,
        project_id=post.project_id,
        referenced_project_id=post.referenced_project_id,
        author_user_id=post.author_user_id,
        author_display_name=author.display_name if author else None,
        body=post.body if post.deleted_at is None else "This post was removed.",
        external_url=post.external_url if post.deleted_at is None else None,
        card_kind=post.card_kind,
        card_size=post.card_size,
        is_pinned=post.is_pinned if post.deleted_at is None else False,
        pinned_at=post.pinned_at if post.deleted_at is None else None,
        created_at=post.created_at,
        edited_at=post.edited_at,
        deleted_at=post.deleted_at,
        attachments=[AssetResponse.model_validate(asset) for asset in assets]
        if post.deleted_at is None
        else [],
        reactions=[
            PostReactionSummary(
                kind=kind,
                count=reaction_counts[kind],
                reacted_by_current_user=kind in current_user_reactions,
            )
            for kind in ReactionKind
            if kind in reaction_counts
        ]
        if post.deleted_at is None
        else [],
    )


@router.get("/bands/{band_id}/posts", response_model=Page[PostResponse])
async def list_posts(
    band_id: uuid.UUID,
    project_id: uuid.UUID | None = None,
    surface: str | None = Query(default=None, pattern="^board$"),
    cursor: str | None = Query(default=None),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Page[PostResponse]:
    await membership_for(session, band_id, user.id)
    if surface == "board" and project_id is not None:
        raise BandAPIError(
            "invalid_post_filter", "Choose either the Band board or a project.", 422
        )
    offset = decode_cursor(cursor)
    blocked_ids = select(UserBlock.blocked_user_id).where(
        UserBlock.blocker_user_id == user.id
    )
    query = select(Post).where(
        Post.band_id == band_id,
        Post.deleted_at.is_(None),
        Post.author_user_id.not_in(blocked_ids),
    )
    if project_id is not None:
        await require_project(session, project_id, band_id)
        query = query.where(Post.project_id == project_id)
    elif surface == "board":
        query = query.where(Post.project_id.is_(None))
    ordering = (
        (Post.is_pinned.desc(), Post.pinned_at.desc(), Post.created_at.desc())
        if surface == "board"
        else (Post.created_at.desc(),)
    )
    posts = list(
        (
            await session.scalars(
                query.order_by(*ordering).offset(offset).limit(PAGE_SIZE + 1)
            )
        ).all()
    )
    has_more = len(posts) > PAGE_SIZE
    return Page(
        items=[
            await build_post_response(session, post, user.id)
            for post in posts[:PAGE_SIZE]
        ],
        next_cursor=encode_cursor(offset + PAGE_SIZE) if has_more else None,
    )


async def validate_board_card(
    session: AsyncSession,
    *,
    band_id: uuid.UUID,
    kind: BandCardKind,
    text: str,
    external_url: str | None,
    assets: list[Asset],
    referenced_project_id: uuid.UUID | None,
) -> tuple[BandCardSize, Project | None]:
    referenced_project = None
    if kind == BandCardKind.note:
        if not text or external_url is not None or assets or referenced_project_id is not None:
            raise BandAPIError("invalid_note_card", "A note card needs text only.", 422)
        return BandCardSize.compact, None
    if kind == BandCardKind.image:
        if not assets or external_url is not None or referenced_project_id is not None:
            raise BandAPIError(
                "invalid_image_card", "An image card needs one to four images.", 422
            )
        if any(asset.kind != AssetKind.image for asset in assets):
            raise BandAPIError("invalid_image_card", "Image cards accept images only.", 422)
        return (BandCardSize.tall if len(assets) == 1 else BandCardSize.wide), None
    if kind == BandCardKind.audio:
        if (
            len(assets) != 1
            or external_url is not None
            or referenced_project_id is not None
        ):
            raise BandAPIError(
                "invalid_audio_card", "An audio card needs one audio file.", 422
            )
        if assets[0].kind != AssetKind.audio:
            raise BandAPIError("invalid_audio_card", "Audio cards accept audio only.", 422)
        return BandCardSize.wide, None
    if kind == BandCardKind.link:
        if external_url is None or assets or referenced_project_id is not None:
            raise BandAPIError("invalid_link_card", "A link card needs one web link.", 422)
        return BandCardSize.compact, None
    if referenced_project_id is None or external_url is not None or assets:
        raise BandAPIError(
            "invalid_project_card", "A project card needs one active Band project.", 422
        )
    referenced_project = await require_project(session, referenced_project_id, band_id)
    if referenced_project.archived_at is not None:
        raise BandAPIError(
            "project_archived", "Choose an active project for this card.", 409
        )
    return BandCardSize.wide, referenced_project


async def existing_post_for_assets(
    session: AsyncSession,
    *,
    band_id: uuid.UUID,
    author_user_id: uuid.UUID,
    project_id: uuid.UUID | None,
    card_kind: BandCardKind,
    asset_ids: list[uuid.UUID],
) -> Post | None:
    if not asset_ids:
        return None
    candidate_ids = list(
        (
            await session.scalars(
                select(PostAttachment.post_id).where(
                    PostAttachment.asset_id == asset_ids[0]
                )
            )
        ).all()
    )
    for post_id in candidate_ids:
        post = await session.get(Post, post_id)
        if (
            post is None
            or post.band_id != band_id
            or post.author_user_id != author_user_id
            or post.project_id != project_id
            or post.card_kind != card_kind
            or post.deleted_at is not None
        ):
            continue
        attached_ids = list(
            (
                await session.scalars(
                    select(PostAttachment.asset_id)
                    .where(PostAttachment.post_id == post.id)
                    .order_by(PostAttachment.display_order)
                )
            ).all()
        )
        if attached_ids == asset_ids:
            return post
    return None


@router.post("/bands/{band_id}/posts", response_model=PostResponse, status_code=201)
async def create_post(
    band_id: uuid.UUID,
    body: PostCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> PostResponse:
    await editable_membership(session, band_id, user.id)
    if body.project_id:
        project = await require_project(session, body.project_id, band_id)
        if project.archived_at:
            raise BandAPIError("project_archived", "Restore this project before posting.", 409)
    text = validate_text(body.body, field="body", maximum=2000, allow_empty=True)
    external_url = validate_external_url(body.external_url)
    mentions = await validate_mentions(
        session,
        band_id=band_id,
        author_user_id=user.id,
        mentioned_user_ids=body.mentioned_user_ids,
    )
    assets: list[Asset] = []
    if body.asset_ids:
        loaded_assets = list(
            (
                await session.scalars(select(Asset).where(Asset.id.in_(body.asset_ids)))
            ).all()
        )
        if len(loaded_assets) != len(set(body.asset_ids)):
            raise BandAPIError("asset_not_found", "One of these uploads is unavailable.", 404)
        assets_by_id = {asset.id: asset for asset in loaded_assets}
        assets = [assets_by_id[asset_id] for asset_id in dict.fromkeys(body.asset_ids)]
        for asset in assets:
            if (
                asset.band_id != band_id
                or asset.status != AssetStatus.ready
                or asset.deleted_at is not None
            ):
                raise BandAPIError("asset_not_ready", "Wait for uploads to finish.", 409)
            if body.project_id is None and asset.kind not in {
                AssetKind.image,
                AssetKind.audio,
            }:
                raise BandAPIError(
                    "project_media_required", "Video must be shared in a project.", 409
                )
            if body.project_id and asset.project_id not in (None, body.project_id):
                raise BandAPIError("asset_project_mismatch", "This upload belongs elsewhere.")
    referenced_project = None
    if body.project_id is None:
        card_size, referenced_project = await validate_board_card(
            session,
            band_id=band_id,
            kind=body.card_kind,
            text=text,
            external_url=external_url,
            assets=assets,
            referenced_project_id=body.referenced_project_id,
        )
    else:
        if body.referenced_project_id is not None:
            raise BandAPIError(
                "invalid_project_reference",
                "Project activity cannot also reference another project.",
                422,
            )
        if not text and external_url is None and not assets:
            raise BandAPIError("empty_post", "Add text, a link, or media.")
        card_size = BandCardSize.compact
    existing_post = await existing_post_for_assets(
        session,
        band_id=band_id,
        author_user_id=user.id,
        project_id=body.project_id,
        card_kind=body.card_kind,
        asset_ids=[asset.id for asset in assets],
    )
    if existing_post is not None:
        return await build_post_response(session, existing_post, user.id)
    post = Post(
        band_id=band_id,
        project_id=body.project_id,
        referenced_project_id=referenced_project.id if referenced_project else None,
        author_user_id=user.id,
        body=text,
        external_url=external_url,
        card_kind=body.card_kind,
        card_size=card_size,
    )
    session.add(post)
    await session.flush()
    for index, asset in enumerate(assets):
        session.add(PostAttachment(post_id=post.id, asset_id=asset.id, display_order=index))
    for mentioned_id in mentions:
        session.add(Mention(mentioned_user_id=mentioned_id, post_id=post.id))
        await create_notification(
            session,
            recipient_user_id=mentioned_id,
            band_id=band_id,
            actor_user_id=user.id,
            kind=NotificationKind.mention,
            entity_type="post",
            entity_id=post.id,
            dedupe_key=f"post-mention:{post.id}:{mentioned_id}",
            send_push=True,
        )
    await session.commit()
    return await build_post_response(session, post, user.id)


@router.patch("/bands/{band_id}/posts/{post_id}", response_model=PostResponse)
async def update_post(
    band_id: uuid.UUID,
    post_id: uuid.UUID,
    body: PostUpdate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> PostResponse:
    _, membership = await editable_membership(session, band_id, user.id)
    post = await session.get(Post, post_id)
    if post is None or post.band_id != band_id or post.project_id is not None:
        raise BandAPIError("post_not_found", "This board card no longer exists.", 404)
    if post.deleted_at is not None:
        raise BandAPIError("post_deleted", "This board card was removed.", 409)

    fields = body.model_fields_set
    content_fields = fields.intersection({"body", "external_url", "referenced_project_id"})
    if content_fields and post.author_user_id != user.id:
        raise BandAPIError(
            "permission_denied", "Only the card author can edit its content.", 403
        )
    if "body" in fields:
        post.body = validate_text(
            body.body or "", field="body", maximum=2000, allow_empty=True
        )
    if "external_url" in fields:
        if post.card_kind != BandCardKind.link:
            raise BandAPIError(
                "invalid_card_edit", "Only link cards have a web link.", 422
            )
        post.external_url = validate_external_url(body.external_url)
    if "referenced_project_id" in fields:
        if post.card_kind != BandCardKind.project or body.referenced_project_id is None:
            raise BandAPIError(
                "invalid_card_edit", "Choose an active project for this card.", 422
            )
        project = await require_project(session, body.referenced_project_id, band_id)
        if project.archived_at is not None:
            raise BandAPIError(
                "project_archived", "Choose an active project for this card.", 409
            )
        post.referenced_project_id = project.id
    if post.card_kind == BandCardKind.note and not post.body:
        raise BandAPIError("invalid_note_card", "A note card needs text.", 422)
    if post.card_kind == BandCardKind.link and post.external_url is None:
        raise BandAPIError("invalid_link_card", "A link card needs one web link.", 422)
    if post.card_kind == BandCardKind.project and post.referenced_project_id is None:
        raise BandAPIError(
            "invalid_project_card", "A project card needs one active project.", 422
        )
    if content_fields:
        post.edited_at = utcnow()

    if "is_pinned" in fields:
        if membership.role not in {BandRole.owner, BandRole.admin}:
            raise BandAPIError(
                "permission_denied", "Only owners and admins can pin cards.", 403
            )
        post.is_pinned = bool(body.is_pinned)
        post.pinned_at = utcnow() if post.is_pinned else None

    await session.commit()
    return await build_post_response(session, post, user.id)


@router.delete("/bands/{band_id}/posts/{post_id}", status_code=204)
async def delete_post(
    band_id: uuid.UUID,
    post_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    _, membership = await editable_membership(session, band_id, user.id)
    post = await session.get(Post, post_id)
    if post is None or post.band_id != band_id:
        raise BandAPIError("post_not_found", "This post no longer exists.", 404)
    if post.author_user_id != user.id and membership.role == BandRole.member:
        raise BandAPIError("permission_denied", "You can’t remove this post.", 403)
    post.deleted_at = utcnow()
    post.is_pinned = False
    post.pinned_at = None
    await session.commit()
    return Response(status_code=204)


async def build_comment_response(
    session: AsyncSession, comment: Comment
) -> CommentResponse:
    author = await session.get(User, comment.author_user_id)
    return CommentResponse(
        id=comment.id,
        post_id=comment.post_id,
        author_user_id=comment.author_user_id,
        author_display_name=author.display_name if author else None,
        parent_comment_id=comment.parent_comment_id,
        body=comment.body if comment.deleted_at is None else "This comment was removed.",
        created_at=comment.created_at,
        edited_at=comment.edited_at,
        deleted_at=comment.deleted_at,
    )


@router.get(
    "/bands/{band_id}/posts/{post_id}/comments", response_model=Page[CommentResponse]
)
async def list_comments(
    band_id: uuid.UUID,
    post_id: uuid.UUID,
    cursor: str | None = Query(default=None),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Page[CommentResponse]:
    await membership_for(session, band_id, user.id)
    post = await session.get(Post, post_id)
    if post is None or post.band_id != band_id:
        raise BandAPIError("post_not_found", "This post no longer exists.", 404)
    offset = decode_cursor(cursor)
    blocked_ids = select(UserBlock.blocked_user_id).where(
        UserBlock.blocker_user_id == user.id
    )
    comments = list(
        (
            await session.scalars(
                select(Comment)
                .where(
                    Comment.post_id == post_id,
                    Comment.author_user_id.not_in(blocked_ids),
                )
                .order_by(Comment.created_at)
                .offset(offset)
                .limit(PAGE_SIZE + 1)
            )
        ).all()
    )
    has_more = len(comments) > PAGE_SIZE
    return Page(
        items=[await build_comment_response(session, item) for item in comments[:PAGE_SIZE]],
        next_cursor=encode_cursor(offset + PAGE_SIZE) if has_more else None,
    )


@router.post(
    "/bands/{band_id}/posts/{post_id}/comments",
    response_model=CommentResponse,
    status_code=201,
)
async def create_comment(
    band_id: uuid.UUID,
    post_id: uuid.UUID,
    body: CommentCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> CommentResponse:
    await editable_membership(session, band_id, user.id)
    post = await session.get(Post, post_id)
    if post is None or post.band_id != band_id or post.deleted_at:
        raise BandAPIError("post_not_found", "This post no longer exists.", 404)
    parent = None
    if body.parent_comment_id:
        parent = await session.get(Comment, body.parent_comment_id)
        if parent is None or parent.post_id != post.id or parent.deleted_at:
            raise BandAPIError("comment_not_found", "This reply no longer exists.", 404)
    mentions = await validate_mentions(
        session,
        band_id=band_id,
        author_user_id=user.id,
        mentioned_user_ids=body.mentioned_user_ids,
    )
    comment = Comment(
        post_id=post.id,
        author_user_id=user.id,
        parent_comment_id=parent.id if parent else None,
        body=validate_text(body.body, field="body", maximum=1000),
    )
    session.add(comment)
    await session.flush()
    recipient = parent.author_user_id if parent else post.author_user_id
    await create_notification(
        session,
        recipient_user_id=recipient,
        band_id=band_id,
        actor_user_id=user.id,
        kind=NotificationKind.reply,
        entity_type="comment",
        entity_id=comment.id,
        dedupe_key=f"reply:{comment.id}:{recipient}",
        send_push=True,
    )
    for mentioned_id in mentions:
        session.add(Mention(mentioned_user_id=mentioned_id, comment_id=comment.id))
        await create_notification(
            session,
            recipient_user_id=mentioned_id,
            band_id=band_id,
            actor_user_id=user.id,
            kind=NotificationKind.mention,
            entity_type="comment",
            entity_id=comment.id,
            dedupe_key=f"comment-mention:{comment.id}:{mentioned_id}",
            send_push=True,
        )
    await session.commit()
    return await build_comment_response(session, comment)


@router.put("/bands/{band_id}/posts/{post_id}/reactions", status_code=204)
async def react_to_post(
    band_id: uuid.UUID,
    post_id: uuid.UUID,
    body: ReactionRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await editable_membership(session, band_id, user.id)
    post = await session.get(Post, post_id)
    if post is None or post.band_id != band_id or post.deleted_at:
        raise BandAPIError("post_not_found", "This post no longer exists.", 404)
    if await blocked_between(session, user.id, post.author_user_id):
        raise BandAPIError("blocked_interaction", "This reaction can’t be sent.", 409)
    existing = await session.scalar(
        select(Reaction).where(
            Reaction.user_id == user.id,
            Reaction.post_id == post.id,
            Reaction.kind == body.kind,
        )
    )
    if existing is None:
        session.add(Reaction(user_id=user.id, post_id=post.id, kind=body.kind))
        await create_notification(
            session,
            recipient_user_id=post.author_user_id,
            band_id=band_id,
            actor_user_id=user.id,
            kind=NotificationKind.reaction,
            entity_type="post",
            entity_id=post.id,
            dedupe_key=f"reaction:{post.id}:{user.id}:{body.kind.value}",
            send_push=False,
        )
        await session.commit()
    return Response(status_code=204)


@router.delete("/bands/{band_id}/posts/{post_id}/reactions/{kind}", status_code=204)
async def remove_post_reaction(
    band_id: uuid.UUID,
    post_id: uuid.UUID,
    kind: str,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await membership_for(session, band_id, user.id)
    await session.execute(
        delete(Reaction).where(
            Reaction.user_id == user.id,
            Reaction.post_id == post_id,
            Reaction.kind == kind,
        )
    )
    await session.commit()
    return Response(status_code=204)
