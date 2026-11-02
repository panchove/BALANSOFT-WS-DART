from __future__ import annotations

import uuid

from pydantic import BaseModel, ConfigDict, Field


class VinculoCreate(BaseModel):
    id_bascula: uuid.UUID = Field(...)
    id_indicador: uuid.UUID = Field(...)


class VinculoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id_vinculo: uuid.UUID
    id_empresa: uuid.UUID
    id_bascula: uuid.UUID
    id_indicador: uuid.UUID
    activo: bool
