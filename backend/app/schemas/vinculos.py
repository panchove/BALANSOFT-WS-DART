from __future__ import annotations

import uuid

from pydantic import BaseModel, Field


class VinculoCreate(BaseModel):
    id_bascula: uuid.UUID = Field(...)
    id_indicador: uuid.UUID = Field(...)


class VinculoOut(BaseModel):
    id_vinculo: uuid.UUID
    id_empresa: uuid.UUID
    id_bascula: uuid.UUID
    id_indicador: uuid.UUID
    activo: bool

    class Config:
        from_attributes = True
