import re
import uuid

from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.band.database import get_session
from app.band.errors import BandAPIError
from app.band.models import (
    SongwritingConversation,
    SongwritingMessage,
    SongwritingMessageRole,
    User,
    utcnow,
)
from app.band.schemas import (
    Page,
    SongwritingConversationCreate,
    SongwritingConversationResponse,
    SongwritingConversationSummary,
    SongwritingLaunchRequest,
    SongwritingLaunchResponse,
    SongwritingMessageCreate,
    SongwritingMessageResponse,
)
from app.band.security import current_user


router = APIRouter(prefix="/v1/songwriting", tags=["Songwriting history"])
MESSAGE_LIMIT = 40
ARCHIVE_LIMIT = 50


def conversation_title(content: str) -> str:
    return re.sub(r"\s+", " ", content).strip()[:80]


async def lock_user(session: AsyncSession, user_id: uuid.UUID) -> None:
    await session.scalar(
        select(User).where(User.id == user_id).with_for_update()
    )


async def active_conversation(
    session: AsyncSession, user_id: uuid.UUID
) -> SongwritingConversation | None:
    return await session.scalar(
        select(SongwritingConversation)
        .where(
            SongwritingConversation.user_id == user_id,
            SongwritingConversation.archived_at.is_(None),
        )
        .order_by(SongwritingConversation.updated_at.desc())
        .limit(1)
    )


async def owned_conversation(
    session: AsyncSession, conversation_id: uuid.UUID, user_id: uuid.UUID
) -> SongwritingConversation:
    conversation = await session.get(SongwritingConversation, conversation_id)
    if conversation is None or conversation.user_id != user_id:
        raise BandAPIError(
            "songwriting_conversation_not_found",
            "This songwriting conversation is unavailable.",
            404,
        )
    return conversation


async def messages_for(
    session: AsyncSession, conversation_id: uuid.UUID
) -> list[SongwritingMessage]:
    return list(
        (
            await session.scalars(
                select(SongwritingMessage)
                .where(SongwritingMessage.conversation_id == conversation_id)
                .order_by(SongwritingMessage.sequence)
            )
        ).all()
    )


async def conversation_response(
    session: AsyncSession, conversation: SongwritingConversation
) -> SongwritingConversationResponse:
    messages = await messages_for(session, conversation.id)
    return SongwritingConversationResponse(
        id=conversation.id,
        title=conversation.title,
        return_count=conversation.return_count,
        archived_at=conversation.archived_at,
        created_at=conversation.created_at,
        updated_at=conversation.updated_at,
        messages=[
            SongwritingMessageResponse.model_validate(message) for message in messages
        ],
    )


async def prune_archives(session: AsyncSession, user_id: uuid.UUID) -> None:
    stale_ids = list(
        (
            await session.scalars(
                select(SongwritingConversation.id)
                .where(
                    SongwritingConversation.user_id == user_id,
                    SongwritingConversation.archived_at.is_not(None),
                )
                .order_by(SongwritingConversation.updated_at.desc())
                .offset(ARCHIVE_LIMIT)
            )
        ).all()
    )
    if stale_ids:
        await session.execute(
            delete(SongwritingConversation).where(
                SongwritingConversation.id.in_(stale_ids)
            )
        )


async def archive(
    session: AsyncSession, conversation: SongwritingConversation
) -> None:
    conversation.archived_at = utcnow()
    conversation.updated_at = utcnow()
    conversation.return_count = 0
    conversation.last_launch_id = None


@router.post("/launch", response_model=SongwritingLaunchResponse)
async def register_launch(
    body: SongwritingLaunchRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SongwritingLaunchResponse:
    await lock_user(session, user.id)
    conversation = await active_conversation(session, user.id)
    if conversation is None:
        return SongwritingLaunchResponse(active=None)
    if conversation.last_launch_id == body.launch_id:
        return SongwritingLaunchResponse(
            active=await conversation_response(session, conversation)
        )
    conversation.last_launch_id = body.launch_id
    conversation.return_count += 1
    conversation.updated_at = utcnow()
    archived_id = None
    if conversation.return_count >= 3:
        archived_id = conversation.id
        await archive(session, conversation)
        await prune_archives(session, user.id)
        await session.commit()
        return SongwritingLaunchResponse(
            active=None, archived_conversation_id=archived_id
        )
    await session.commit()
    return SongwritingLaunchResponse(
        active=await conversation_response(session, conversation)
    )


@router.post(
    "/conversations",
    response_model=SongwritingConversationResponse,
    status_code=201,
)
async def create_conversation(
    body: SongwritingConversationCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SongwritingConversationResponse:
    await lock_user(session, user.id)
    existing = await session.get(SongwritingConversation, body.id)
    if existing is not None:
        if existing.user_id != user.id:
            raise BandAPIError(
                "songwriting_conversation_not_found",
                "This songwriting conversation is unavailable.",
                404,
            )
        return await conversation_response(session, existing)
    current = await active_conversation(session, user.id)
    if current is not None:
        await archive(session, current)
    now = utcnow()
    content = body.content.strip()
    conversation = SongwritingConversation(
        id=body.id,
        user_id=user.id,
        title=conversation_title(content),
        created_at=now,
        updated_at=now,
    )
    session.add(conversation)
    session.add(
        SongwritingMessage(
            id=body.message_id,
            conversation_id=conversation.id,
            role=SongwritingMessageRole.user,
            content=content,
            sequence=0,
            created_at=now,
        )
    )
    await prune_archives(session, user.id)
    await session.commit()
    return await conversation_response(session, conversation)


@router.put(
    "/conversations/{conversation_id}/messages/{message_id}",
    response_model=SongwritingConversationResponse,
)
async def append_message(
    conversation_id: uuid.UUID,
    message_id: uuid.UUID,
    body: SongwritingMessageCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SongwritingConversationResponse:
    await lock_user(session, user.id)
    conversation = await owned_conversation(session, conversation_id, user.id)
    if conversation.archived_at is not None:
        raise BandAPIError(
            "songwriting_conversation_archived",
            "Resume this conversation before adding to it.",
            409,
        )
    existing = await session.get(SongwritingMessage, message_id)
    if existing is not None:
        if existing.conversation_id != conversation.id:
            raise BandAPIError(
                "songwriting_message_conflict",
                "This message identifier is already in use.",
                409,
            )
        return await conversation_response(session, conversation)
    content = body.content.strip()
    maximum = 1200 if body.role == SongwritingMessageRole.user else 6000
    if not content or len(content) > maximum:
        raise BandAPIError(
            "invalid_songwriting_message",
            f"Messages are limited to {maximum} characters.",
            422,
        )
    sequence = (
        await session.scalar(
            select(func.max(SongwritingMessage.sequence)).where(
                SongwritingMessage.conversation_id == conversation.id
            )
        )
        or 0
    ) + 1
    session.add(
        SongwritingMessage(
            id=message_id,
            conversation_id=conversation.id,
            role=body.role,
            content=content,
            sequence=sequence,
        )
    )
    conversation.updated_at = utcnow()
    await session.flush()
    stale_ids = list(
        (
            await session.scalars(
                select(SongwritingMessage.id)
                .where(SongwritingMessage.conversation_id == conversation.id)
                .order_by(SongwritingMessage.sequence.desc())
                .offset(MESSAGE_LIMIT)
            )
        ).all()
    )
    if stale_ids:
        await session.execute(
            delete(SongwritingMessage).where(SongwritingMessage.id.in_(stale_ids))
        )
    await session.commit()
    return await conversation_response(session, conversation)


@router.get(
    "/conversations",
    response_model=Page[SongwritingConversationSummary],
)
async def list_conversations(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Page[SongwritingConversationSummary]:
    conversations = list(
        (
            await session.scalars(
                select(SongwritingConversation)
                .where(
                    SongwritingConversation.user_id == user.id,
                    SongwritingConversation.archived_at.is_not(None),
                )
                .order_by(SongwritingConversation.updated_at.desc())
                .limit(ARCHIVE_LIMIT)
            )
        ).all()
    )
    summaries = []
    for conversation in conversations:
        messages = await messages_for(session, conversation.id)
        summaries.append(
            SongwritingConversationSummary(
                id=conversation.id,
                title=conversation.title,
                preview=messages[-1].content[:120] if messages else "",
                message_count=len(messages),
                created_at=conversation.created_at,
                updated_at=conversation.updated_at,
            )
        )
    return Page(items=summaries)


@router.get(
    "/conversations/{conversation_id}",
    response_model=SongwritingConversationResponse,
)
async def get_conversation(
    conversation_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SongwritingConversationResponse:
    conversation = await owned_conversation(session, conversation_id, user.id)
    return await conversation_response(session, conversation)


@router.post(
    "/conversations/{conversation_id}/resume",
    response_model=SongwritingConversationResponse,
)
async def resume_conversation(
    conversation_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SongwritingConversationResponse:
    await lock_user(session, user.id)
    selected = await owned_conversation(session, conversation_id, user.id)
    current = await active_conversation(session, user.id)
    if current is not None and current.id != selected.id:
        await archive(session, current)
    selected.archived_at = None
    selected.return_count = 0
    selected.last_launch_id = None
    selected.updated_at = utcnow()
    await prune_archives(session, user.id)
    await session.commit()
    return await conversation_response(session, selected)


@router.delete("/conversations/{conversation_id}", status_code=204)
async def delete_conversation(
    conversation_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    conversation = await owned_conversation(session, conversation_id, user.id)
    if conversation.archived_at is None:
        raise BandAPIError(
            "songwriting_conversation_active",
            "Only saved conversations can be deleted.",
            409,
        )
    await session.delete(conversation)
    await session.commit()
    return Response(status_code=204)


@router.delete("/conversations", status_code=204)
async def clear_conversations(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> Response:
    await session.execute(
        delete(SongwritingConversation).where(
            SongwritingConversation.user_id == user.id,
            SongwritingConversation.archived_at.is_not(None),
        )
    )
    await session.commit()
    return Response(status_code=204)
