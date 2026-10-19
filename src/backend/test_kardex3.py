import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import text
from app.models import Empresa
from app.services.report_service import ReportService
from datetime import datetime

async def main():
    engine = create_async_engine("postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws")
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with async_session() as db:
        res_empresa = await db.execute(text("SELECT id_empresa FROM empresa LIMIT 1"))
        id_empresa = res_empresa.scalar()
        if not id_empresa:
            print("No empresa found")
            return
            
        empresa = Empresa(id_empresa=id_empresa)
        service = ReportService()
        res = await service.kardex_detalle(
            db, 
            empresa, 
            datetime(2026, 9, 1), 
            datetime(2026, 9, 22)
        )
        import json
        print(json.dumps(res, indent=2))

asyncio.run(main())
